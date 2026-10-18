-- Cashier/owner server boundary (pre-Shop #1 security phase).
--
-- Until now the tablet kept the owner's Supabase session underneath cashier
-- mode, so every cashier-mode request reached the server as the owner. The app
-- now signs the owner out before cashier mode and runs it on a session-less
-- client that presents a device credential instead. This migration gives that
-- credential exactly the authority cashier billing needs, and nothing else:
--
-- 1. Device credential. A random 256-bit secret per registered device, issued
--    only to the shop's owner (issue_device_credential) and stored here only as
--    its SHA-256 hash, in a schema PostgREST does not expose. Issuing again
--    rotates it (the old secret stops working); a deactivated device's
--    credential stops working at once. The app sends it as the request header
--    x-dukaan-device: <device id>.<secret hex>.
--
-- 2. Cashier operations (sync_sale_transaction, sync_customer_payment). The
--    device credential authenticates the device, never the cashier. An upload
--    authenticated by it is accepted only with a cashier session proof:
--      - live: a valid cashier token for the same shop, device and cashier
--        (the existing path, unchanged), or
--      - historical: a cashier_sessions row for the same shop, device and
--        cashier whose validity window [created_at, least(expires_at,
--        revoked_at)] contains the operation's created_at (5 minutes of
--        clock-skew tolerance each side). This lets a sale or payment made
--        offline during a session sync after the cashier logged out or the
--        session expired. It reads cashier_sessions only: it never extends,
--        reopens or revalidates a session, and grants nothing else.
--    A proven historical upload runs the unchanged R1 function chain as the
--    shop's owner, the idiom migration 4 already uses for cashier tokens, so
--    payload validation, idempotency, stable codes and record-and-flag are
--    exactly as before. Owner JWT calls and calls without a device credential
--    (old APKs) take the previous path unchanged.
--
-- 3. Device read path. device_pull returns one page of the 15 entities the
--    cashier runtime pulls, for the credential's own shop only, with the
--    columns ReferencePullService consumes (no aggregate/operation hashes, no
--    PIN hash, no shop_users, no cashier_sessions) and the R1.4 cursor
--    ((server_seq, id) order, strictly after the given position). No table
--    grant or RLS policy changes for anon.
--
-- 4. Grant hygiene. suppliers, purchases, purchase_items, purchase_payments,
--    supplier_ledger_entries, expense_categories and expenses were created
--    after the deny-by-default baseline and inherited TRUNCATE, TRIGGER and
--    REFERENCES for anon and authenticated (TRUNCATE ignores RLS). Clients
--    keep only SELECT for authenticated, which the owner pull needs; writes
--    go through the existing RPCs.
--
-- Forward-only and additive: no row is changed. The previous sync functions
-- are kept as <name>_coded_legacy (the idiom of migrations 4, 13 and 21).
begin;

create schema if not exists dukaan_private;
revoke all on schema dukaan_private from public, anon, authenticated;

create table dukaan_private.device_credentials (
  device_id uuid primary key,
  shop_id uuid not null,
  credential_hash bytea not null check (octet_length(credential_hash) = 32),
  issued_at timestamptz not null default now(),
  foreign key (device_id, shop_id) references public.devices(id, shop_id) on delete cascade
);
alter table dukaan_private.device_credentials enable row level security;
revoke all on table dukaan_private.device_credentials from public, anon, authenticated;

-- Owner-only provisioning. Returns the plaintext secret once; only its hash is
-- kept. Issuing again rotates the credential.
create function public.issue_device_credential(p_shop_id uuid, p_device_id uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare v_secret text;
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if not exists(select 1 from public.devices d
                where d.id = p_device_id and d.shop_id = p_shop_id and d.is_active) then
    raise exception 'active device required' using errcode = '42501';
  end if;
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into dukaan_private.device_credentials(device_id, shop_id, credential_hash, issued_at)
  values (p_device_id, p_shop_id, extensions.digest(convert_to(v_secret, 'UTF8'), 'sha256'), now())
  on conflict (device_id) do update
    set shop_id = excluded.shop_id,
        credential_hash = excluded.credential_hash,
        issued_at = excluded.issued_at;
  return v_secret;
end $$;
revoke all on function public.issue_device_credential(uuid, uuid) from public, anon, authenticated;
grant execute on function public.issue_device_credential(uuid, uuid) to authenticated;

-- The request's device, from the x-dukaan-device header: exactly one active
-- device and its shop, or nulls. Fails closed on any malformed input.
create function dukaan_private.request_device(out shop_id uuid, out device_id uuid)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_header text;
  v_device uuid;
  v_secret text;
begin
  begin
    v_header := nullif(current_setting('request.headers', true), '')::json ->> 'x-dukaan-device';
    if v_header is null
       or v_header !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[0-9a-f]{64}$' then
      return;
    end if;
    v_device := split_part(v_header, '.', 1)::uuid;
    v_secret := split_part(v_header, '.', 2);
  exception when others then
    return;
  end;
  select c.shop_id, c.device_id into shop_id, device_id
    from dukaan_private.device_credentials c
    join public.devices d on d.id = c.device_id and d.shop_id = c.shop_id
   where c.device_id = v_device
     and d.is_active
     and c.credential_hash = extensions.digest(convert_to(v_secret, 'UTF8'), 'sha256');
end $$;
revoke all on function dukaan_private.request_device() from public, anon, authenticated;

-- Decides how a cashier-attributed operation is authorised.
--   'direct' - run the previous function unchanged: owner JWT, no device
--              credential (old APK), unparseable payload (the previous chain
--              reports it as before), or a live token for this exact
--              shop/device/cashier (the previous chain validates it itself).
--   'proven' - device credential plus a historical session of this cashier on
--              this device covering the operation's created_at.
-- Otherwise raises: DPA01 for a credential of another shop/device or an
-- inactive cashier, 42501 when no session proof exists.
create function dukaan_private.cashier_operation_authority(
  p_shop_id uuid, p_device_id uuid, p_cashier_id uuid, p_created_at timestamptz, p_token text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_device record;
  v_token_cashier uuid;
begin
  if p_shop_id is null or public.is_active_owner(p_shop_id) then
    return 'direct';
  end if;
  select * into v_device from dukaan_private.request_device();
  if v_device.shop_id is null then
    return 'direct';
  end if;
  if v_device.shop_id <> p_shop_id or v_device.device_id is distinct from p_device_id then
    raise exception 'DPA01: device credential does not belong to this shop and device'
      using errcode = 'DPA01';
  end if;
  if p_cashier_id is null or p_created_at is null then
    return 'direct';
  end if;
  if p_token is not null then
    select s.cashier_id into v_token_cashier
      from public.cashier_sessions s
     where s.token_hash = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256')
       and s.shop_id = p_shop_id and s.device_id = p_device_id
       and s.revoked_at is null and s.expires_at > now();
    if v_token_cashier = p_cashier_id then
      return 'direct';
    end if;
  end if;
  if not exists(select 1 from public.cashiers c
                where c.id = p_cashier_id and c.shop_id = p_shop_id and c.is_active) then
    raise exception 'DPA01: inactive or foreign cashier' using errcode = 'DPA01';
  end if;
  if exists(
    select 1 from public.cashier_sessions s
     where s.shop_id = p_shop_id and s.device_id = p_device_id and s.cashier_id = p_cashier_id
       and p_created_at >= s.created_at - interval '5 minutes'
       and p_created_at <= least(s.expires_at, coalesce(s.revoked_at, s.expires_at)) + interval '5 minutes'
  ) then
    return 'proven';
  end if;
  raise exception 'cashier session proof required' using errcode = '42501';
end $$;
revoke all on function dukaan_private.cashier_operation_authority(uuid, uuid, uuid, timestamptz, text)
  from public, anon, authenticated;

-- The shop's first active owner, for a proven call (same choice as migration 4).
create function dukaan_private.shop_owner(p_shop_id uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select su.user_id from public.shop_users su
   where su.shop_id = p_shop_id and su.role = 'owner' and su.is_active
   order by su.created_at limit 1;
$$;
revoke all on function dukaan_private.shop_owner(uuid) from public, anon, authenticated;

alter function public.sync_sale_transaction(jsonb, text)
  rename to sync_sale_transaction_coded_legacy;
revoke all on function public.sync_sale_transaction_coded_legacy(jsonb, text)
  from public, anon, authenticated;

create function public.sync_sale_transaction(p_payload jsonb, p_cashier_token text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_shop uuid; v_device uuid; v_cashier uuid; v_at timestamptz;
  v_owner uuid; v_sub text; v_result jsonb;
begin
  begin
    v_shop := (p_payload -> 'sale' ->> 'shopId')::uuid;
    v_device := (p_payload -> 'sale' ->> 'deviceId')::uuid;
    v_cashier := (p_payload -> 'sale' ->> 'cashierId')::uuid;
    v_at := (p_payload -> 'sale' ->> 'createdAt')::timestamptz;
  exception when others then
    v_shop := null;
  end;
  if dukaan_private.cashier_operation_authority(v_shop, v_device, v_cashier, v_at, p_cashier_token) = 'direct' then
    return public.sync_sale_transaction_coded_legacy(p_payload, p_cashier_token);
  end if;
  v_owner := dukaan_private.shop_owner(v_shop);
  if v_owner is null then
    raise exception 'DPA01: shop has no active owner' using errcode = 'DPA01';
  end if;
  v_sub := current_setting('request.jwt.claim.sub', true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  begin
    v_result := public.sync_sale_transaction_coded_legacy(p_payload, null);
  exception when others then
    perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  return v_result;
end $$;
revoke all on function public.sync_sale_transaction(jsonb, text) from public, anon, authenticated;
grant execute on function public.sync_sale_transaction(jsonb, text) to anon, authenticated;

alter function public.sync_customer_payment(jsonb, text)
  rename to sync_customer_payment_coded_legacy;
revoke all on function public.sync_customer_payment_coded_legacy(jsonb, text)
  from public, anon, authenticated;

create function public.sync_customer_payment(p_payload jsonb, p_cashier_token text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_shop uuid; v_device uuid; v_cashier uuid; v_at timestamptz;
  v_owner uuid; v_sub text; v_result jsonb;
begin
  begin
    v_shop := (p_payload -> 'entry' ->> 'shop_id')::uuid;
    v_device := (p_payload -> 'audit' ->> 'device_id')::uuid;
    v_cashier := (p_payload -> 'entry' ->> 'created_by')::uuid;
    v_at := (p_payload -> 'entry' ->> 'created_at')::timestamptz;
  exception when others then
    v_shop := null;
  end;
  if dukaan_private.cashier_operation_authority(v_shop, v_device, v_cashier, v_at, p_cashier_token) = 'direct' then
    return public.sync_customer_payment_coded_legacy(p_payload, p_cashier_token);
  end if;
  v_owner := dukaan_private.shop_owner(v_shop);
  if v_owner is null then
    raise exception 'DPA01: shop has no active owner' using errcode = 'DPA01';
  end if;
  v_sub := current_setting('request.jwt.claim.sub', true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  begin
    v_result := public.sync_customer_payment_coded_legacy(p_payload, null);
  exception when others then
    perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  return v_result;
end $$;
revoke all on function public.sync_customer_payment(jsonb, text) from public, anon, authenticated;
grant execute on function public.sync_customer_payment(jsonb, text) to anon, authenticated;

-- One page of a pulled entity for the credential's own shop, in R1.4 cursor
-- order. p_after_seq null starts from the beginning; p_after_id null means
-- "after this server_seq" (the client's cursor without an entity id).
create function public.device_pull(
  p_entity text, p_after_seq bigint default null, p_after_id uuid default null,
  p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_device record;
  v_table text;
  v_columns text;
  v_filter text;
  v_rows jsonb;
begin
  select * into v_device from dukaan_private.request_device();
  if v_device.shop_id is null then
    raise exception 'device credential required' using errcode = '42501';
  end if;
  case p_entity
    when 'shops' then
      v_table := 'shops'; v_filter := 'id = $1';
      v_columns := 'id,name,phone,address,currency,timezone,subscription_plan,subscription_status,'
        'allow_negative_stock,created_at,updated_at,default_low_stock_level,receipt_footer,'
        'receipt_paper_width,receipt_show_phone,receipt_show_address,notifications_enabled,server_seq';
    when 'devices' then
      v_table := 'devices'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,device_name,device_type,device_identifier,is_active,last_seen_at,'
        'last_synced_at,created_at,updated_at,server_seq';
    when 'cashiers' then
      v_table := 'cashiers'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,display_name,login_code,credential_version,is_active,created_at,'
        'updated_at,server_seq';
    when 'categories' then
      v_table := 'categories'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,name,is_active,created_at,updated_at,server_seq';
    when 'globalCategories' then
      v_table := 'categories'; v_filter := 'shop_id is null and $1 is not null';
      v_columns := 'id,shop_id,name,is_active,created_at,updated_at,server_seq';
    when 'masterProducts' then
      v_table := 'master_products'; v_filter := '$1 is not null';
      v_columns := 'id,barcode,name,brand,category_id,default_image_path,default_unit,created_at,'
        'updated_at,is_active,pack_label,server_seq';
    when 'shopProducts' then
      v_table := 'shop_products'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,master_product_id,custom_name,barcode,purchase_price,sale_price,'
        'stock_tracking_enabled,low_stock_level,is_active,created_at,updated_at,category_id,unit,'
        'pack_label,image_path,server_seq';
    when 'customers' then
      v_table := 'customers'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,name,phone,address,credit_limit,is_active,created_at,updated_at,'
        'notes,server_seq';
    when 'customerLedgerEntries' then
      v_table := 'customer_ledger_entries'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,customer_id,type,amount,sale_id,payment_reference,note,created_by,'
        'created_at,payment_method,server_seq';
    when 'inventoryMovements' then
      v_table := 'inventory_movements'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,product_id,type,quantity,reference_type,reference_id,note,'
        'created_by,device_id,created_at,server_seq';
    when 'sales' then
      v_table := 'sales'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,cashier_id,customer_id,device_id,invoice_number,subtotal,'
        'discount_total,tax_total,grand_total,payment_status,sale_status,created_at,synced_at,'
        'server_seq';
    when 'saleItems' then
      v_table := 'sale_items'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,sale_id,product_id,product_name_snapshot,barcode_snapshot,quantity,'
        'cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at,server_seq';
    when 'salePayments' then
      v_table := 'sale_payments'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,sale_id,payment_method,amount,reference,created_at,server_seq';
    when 'saleReturns' then
      v_table := 'sale_returns'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,original_sale_id,customer_id,device_id,refund_method,refund_amount,'
        'reason,created_by,created_at,synced_at,server_seq';
    when 'saleReturnItems' then
      v_table := 'sale_return_items'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,return_id,original_sale_item_id,product_id,product_name_snapshot,'
        'quantity,unit_price_snapshot,refund_amount,created_at,server_seq';
    when 'saleVoids' then
      v_table := 'sale_voids'; v_filter := 'shop_id = $1';
      v_columns := 'id,shop_id,original_sale_id,device_id,amount,reason,payment_breakdown,'
        'created_by,created_at,synced_at,server_seq';
    else
      raise exception 'unsupported pull entity' using errcode = '22023';
  end case;
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(t) order by t.server_seq, t.id), ''[]''::jsonb) from ('
    'select %s from public.%I where %s and ($2::bigint is null or server_seq > $2 '
    'or ($3::uuid is not null and server_seq = $2 and id > $3)) '
    'order by server_seq, id limit $4) t',
    v_columns, v_table, v_filter)
  into v_rows
  using v_device.shop_id, p_after_seq, p_after_id, least(greatest(coalesce(p_limit, 100), 1), 500);
  return v_rows;
end $$;
revoke all on function public.device_pull(text, bigint, uuid, integer) from public, anon, authenticated;
grant execute on function public.device_pull(text, bigint, uuid, integer) to anon;

-- Grant hygiene: SELECT for the owner pull only; writes stay behind the RPCs.
revoke all on table public.suppliers, public.purchases, public.purchase_items,
  public.purchase_payments, public.supplier_ledger_entries, public.expense_categories,
  public.expenses from public, anon, authenticated;
grant select on table public.suppliers, public.purchases, public.purchase_items,
  public.purchase_payments, public.supplier_ledger_entries, public.expense_categories,
  public.expenses to authenticated;

do $$
declare t text;
begin
  foreach t in array array['suppliers','purchases','purchase_items','purchase_payments',
    'supplier_ledger_entries','expense_categories','expenses'] loop
    if not (select c.relrowsecurity from pg_class c
            where c.oid = format('public.%I', t)::regclass) then
      raise exception 'RLS is not enabled on public.%', t;
    end if;
  end loop;
end $$;

commit;
