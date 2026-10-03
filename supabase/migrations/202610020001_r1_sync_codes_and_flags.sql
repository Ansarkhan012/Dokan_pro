-- R1.5 (findings F-3 / O-4): stable sync error codes and record-and-flag.
--
-- A device queues an operation offline and uploads it later. Two outcomes used
-- to be indistinguishable plain exceptions that the device retried forever:
--
-- 1. The upload can never succeed unchanged. The four R1 sync RPCs (sale,
--    customer payment, void, return) now raise a stable SQLSTATE the client
--    classifies without reading message text (design sections H and I):
--      DPV01  invalid or obsolete payload (validation failures, malformed
--             values such as a zero-amount payment row; v1 voids since R1.3)
--      DPC01  same operation id with different content (conflicting replay)
--      DPX01  valid payload that conflicts with the cloud and is not applied:
--             second void, void of a returned sale, return of a voided sale,
--             return beyond the sold quantity
--      DPA01  device or cashier is inactive or foreign
--    Other 42501 (authorisation) errors pass through unchanged. Every other
--    error keeps its own SQLSTATE and message; in particular the approved
--    record-and-flag cases that are not implemented yet (inactive customer,
--    customer overpayment, out-of-window void) and a missing original sale
--    keep their current errors.
--
-- 2. The sale is valid but broke a shop rule that the device could not see
--    offline (design section I). Today that rule is the customer credit
--    limit: two devices each saw room under the limit. The sale is a real
--    sale, so it is recorded and flagged instead of rejected: the credit-limit
--    trigger inserts a sync_exceptions row instead of raising, only while
--    sync_sale_transaction has set dukaan.sync_policy = 'record_and_flag' in
--    its own transaction. Every other path (no policy set) still raises as
--    before. The result is {"status":"accepted_flagged","flags":[...]}; a
--    replay answers already_synced and carries the same flags.
--
-- Forward-only and additive: one new table; each RPC is wrapped (the previous
-- function is kept as <name>_validated_legacy, the idiom of migrations 4 and
-- 13) and the credit-limit trigger function is replaced. The wrappers only
-- translate errors: every accepted operation, hash, row and replay is exactly
-- what the wrapped function produces. No row is changed.
begin;

create table public.sync_exceptions(
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  rule_code text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(shop_id, entity_type, entity_id, rule_code)
);
alter table public.sync_exceptions enable row level security;
revoke all on public.sync_exceptions from public, anon, authenticated;
grant select on public.sync_exceptions to authenticated;
create policy sync_exceptions_owner_select on public.sync_exceptions
  for select to authenticated using (public.is_active_owner(shop_id));

-- Unchanged except for the record_and_flag branch.
create or replace function public.enforce_customer_credit_limit() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare v_limit bigint; v_balance bigint;
begin
  if new.type <> 'creditSale' then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended(new.customer_id::text, 0));
  select credit_limit into v_limit from public.customers
    where id=new.customer_id and shop_id=new.shop_id and is_active;
  if not found then raise exception 'active customer required'; end if;
  if v_limit is null then return new; end if;
  select coalesce(sum(case
    when type in ('openingBalance','creditSale','adjustment') then amount
    when type in ('paymentReceived','refund') then -amount end),0)
    into v_balance from public.customer_ledger_entries
    where shop_id=new.shop_id and customer_id=new.customer_id;
  if v_balance + new.amount > v_limit then
    if current_setting('dukaan.sync_policy', true) = 'record_and_flag'
       and new.sale_id is not null then
      insert into public.sync_exceptions(shop_id, entity_type, entity_id, rule_code, detail)
      values (new.shop_id, 'sale', new.sale_id, 'credit_limit_exceeded',
        jsonb_build_object('customer_id', new.customer_id, 'credit_limit', v_limit,
          'balance_before', v_balance, 'amount', new.amount))
      on conflict (shop_id, entity_type, entity_id, rule_code) do nothing;
      return new;
    end if;
    raise exception 'customer credit limit exceeded' using errcode = '23514';
  end if;
  return new;
end; $$;
revoke all on function public.enforce_customer_credit_limit() from public, anon, authenticated;

-- The single translation from the wrapped functions' own fixed messages to
-- stable codes. Always raises. An error that already carries a DP code (the
-- R1.3 v1-void DPV01) passes through.
create function public.r1_raise_stable_sync_error(p_state text, p_message text)
returns void language plpgsql set search_path = public, pg_temp as $$
begin
  if p_state like 'DP%' then
    raise exception using errcode = p_state, message = p_message;
  elsif p_message in ('inactive or foreign device', 'inactive or foreign cashier',
                      'shop has no active owner', 'active device required',
                      'active shop device required') then
    raise exception using errcode = 'DPA01', message = 'DPA01: ' || p_message;
  elsif p_state = '42501' then
    raise exception using errcode = p_state, message = p_message;
  elsif p_message in ('conflicting replay for immutable sale',
                      'existing sale predates aggregate fingerprint',
                      'conflicting replay for immutable customer payment',
                      'conflicting replay for immutable void',
                      'conflicting replay for immutable return') then
    raise exception using errcode = 'DPC01', message = 'DPC01: ' || p_message;
  elsif p_message in ('sale already voided', 'sale with returns cannot be voided',
                      'voided sale cannot be returned', 'return exceeds sold quantity') then
    raise exception using errcode = 'DPX01', message = 'DPX01: ' || p_message;
  elsif p_state like '22%' or p_message in (
      -- sale
      'unsupported sale payload', 'sale requires items', 'invalid sale item',
      'sale item total mismatch', 'sale header total mismatch', 'invalid sale payment',
      'sale inventory does not match items', 'invalid sale inventory movement',
      'unexpected credit ledger', 'credit ledger mismatch', 'payment total mismatch',
      'credit requires customer',
      -- customer payment
      'invalid customer payment',
      -- void
      'void amount mismatch', 'void payment breakdown mismatch',
      'void compensation ids do not match the sale items', 'void refund ledger id mismatch',
      -- return
      'invalid return payload', 'invalid original sale item', 'return item refund mismatch',
      'return refund mismatch', 'return inventory does not match items',
      'credit refund requires customer', 'invalid return inventory movement') then
    raise exception using errcode = 'DPV01', message = 'DPV01: ' || p_message;
  end if;
  raise exception using errcode = p_state, message = p_message;
end $$;
revoke all on function public.r1_raise_stable_sync_error(text,text) from public, anon, authenticated;

alter function public.sync_sale_transaction(jsonb,text)
  rename to sync_sale_transaction_validated_legacy;
revoke all on function public.sync_sale_transaction_validated_legacy(jsonb,text)
  from public, anon, authenticated;

create function public.sync_sale_transaction(p_payload jsonb, p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path = public, extensions, pg_temp as $$
declare
  v_sale_id uuid;
  v_shop_id uuid;
  v_result jsonb;
  v_flags jsonb;
  v_state text;
  v_message text;
begin
  begin
    v_sale_id := (p_payload->'sale'->>'id')::uuid;
    v_shop_id := (p_payload->'sale'->>'shopId')::uuid;
  exception when others then
    raise exception 'DPV01: sale payload has no valid sale or shop id' using errcode = 'DPV01';
  end;
  if v_sale_id is null or v_shop_id is null then
    raise exception 'DPV01: sale payload has no valid sale or shop id' using errcode = 'DPV01';
  end if;

  perform set_config('dukaan.sync_policy', 'record_and_flag', true);
  begin
    v_result := public.sync_sale_transaction_validated_legacy(p_payload, p_cashier_token);
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    perform set_config('dukaan.sync_policy', '', true);
    perform public.r1_raise_stable_sync_error(v_state, v_message);
  end;
  perform set_config('dukaan.sync_policy', '', true);

  select coalesce(jsonb_agg(rule_code order by rule_code), '[]'::jsonb) into v_flags
    from public.sync_exceptions
    where shop_id = v_shop_id and entity_type = 'sale' and entity_id = v_sale_id;
  if jsonb_array_length(v_flags) > 0 then
    v_result := v_result || jsonb_build_object('flags', v_flags);
    if v_result->>'status' = 'inserted' then
      v_result := v_result || jsonb_build_object('status', 'accepted_flagged');
    end if;
  end if;
  return v_result;
end $$;

revoke all on function public.sync_sale_transaction(jsonb,text) from public, anon, authenticated;
grant execute on function public.sync_sale_transaction(jsonb,text) to anon, authenticated;

-- Customer payment, void and return: same codes, results unchanged.
alter function public.sync_customer_payment(jsonb,text)
  rename to sync_customer_payment_validated_legacy;
alter function public.sync_sale_void(jsonb,text)
  rename to sync_sale_void_validated_legacy;
alter function public.sync_sale_return(jsonb,text)
  rename to sync_sale_return_validated_legacy;
revoke all on function public.sync_customer_payment_validated_legacy(jsonb,text),
  public.sync_sale_void_validated_legacy(jsonb,text),
  public.sync_sale_return_validated_legacy(jsonb,text) from public, anon, authenticated;

create function public.sync_customer_payment(p_payload jsonb, p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path = public, extensions, pg_temp as $$
declare v_state text; v_message text;
begin
  return public.sync_customer_payment_validated_legacy(p_payload, p_cashier_token);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
  perform public.r1_raise_stable_sync_error(v_state, v_message);
  return null; -- unreachable: the call above always raises
end $$;

create function public.sync_sale_void(p_payload jsonb, p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path = public, extensions, pg_temp as $$
declare v_state text; v_message text;
begin
  return public.sync_sale_void_validated_legacy(p_payload, p_cashier_token);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
  perform public.r1_raise_stable_sync_error(v_state, v_message);
  return null; -- unreachable: the call above always raises
end $$;

create function public.sync_sale_return(p_payload jsonb, p_cashier_token text default null)
returns jsonb language plpgsql security definer
set search_path = public, extensions, pg_temp as $$
declare v_state text; v_message text;
begin
  return public.sync_sale_return_validated_legacy(p_payload, p_cashier_token);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
  perform public.r1_raise_stable_sync_error(v_state, v_message);
  return null; -- unreachable: the call above always raises
end $$;

-- Same callers as before: payments from owner or cashier sessions, voids and
-- returns from owners only.
revoke all on function public.sync_customer_payment(jsonb,text),
  public.sync_sale_void(jsonb,text), public.sync_sale_return(jsonb,text)
  from public, anon, authenticated;
grant execute on function public.sync_customer_payment(jsonb,text) to anon, authenticated;
grant execute on function public.sync_sale_void(jsonb,text),
  public.sync_sale_return(jsonb,text) to authenticated;
commit;
