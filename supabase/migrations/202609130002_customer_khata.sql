begin;

alter table public.customers add column notes text;
alter table public.customer_ledger_entries
  add column payment_method public.payment_method,
  add column operation_hash bytea;

alter table public.customer_ledger_entries
  add constraint customer_ledger_positive_magnitude check (amount > 0),
  add constraint customer_payment_method_valid check (
    (type = 'paymentReceived' and (payment_method is null or payment_method in ('cash','digital'))) or
    (type <> 'paymentReceived' and payment_method is null)
  );

grant update(notes) on table public.customers to authenticated;

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
    raise exception 'customer credit limit exceeded' using errcode = '23514';
  end if;
  return new;
end; $$;
create trigger customer_credit_limit_before_insert before insert on public.customer_ledger_entries
for each row execute function public.enforce_customer_credit_limit();
revoke all on function public.enforce_customer_credit_limit() from public, anon, authenticated;

create or replace function public.save_customer(
  p_shop_id uuid, p_customer_id uuid, p_name text, p_phone text default null,
  p_address text default null, p_notes text default null,
  p_credit_limit bigint default null, p_is_active boolean default true
) returns uuid
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid := coalesce(p_customer_id, extensions.gen_random_uuid());
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_name,''))) = 0 then raise exception 'customer name required'; end if;
  if p_credit_limit is not null and p_credit_limit < 0 then raise exception 'credit limit cannot be negative'; end if;
  if p_customer_id is null then
    insert into public.customers(id,shop_id,name,phone,address,notes,credit_limit,is_active,created_at,updated_at)
    values(v_id,p_shop_id,trim(p_name),nullif(trim(coalesce(p_phone,'')),''),
      nullif(trim(coalesce(p_address,'')),''),nullif(trim(coalesce(p_notes,'')),''),
      p_credit_limit,p_is_active,now(),now());
  else
    update public.customers set name=trim(p_name),phone=nullif(trim(coalesce(p_phone,'')),''),
      address=nullif(trim(coalesce(p_address,'')),''),notes=nullif(trim(coalesce(p_notes,'')),''),
      credit_limit=p_credit_limit,is_active=p_is_active,updated_at=now()
    where id=p_customer_id and shop_id=p_shop_id;
    if not found then raise exception 'customer not found'; end if;
  end if;
  return v_id;
end; $$;

create or replace function public.sync_customer_payment(p_payload jsonb, p_cashier_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_entry jsonb := p_payload -> 'entry';
  v_audit jsonb := p_payload -> 'audit';
  v_entry_id uuid := (v_entry ->> 'id')::uuid;
  v_shop_id uuid := (v_entry ->> 'shop_id')::uuid;
  v_customer_id uuid := (v_entry ->> 'customer_id')::uuid;
  v_actor_id uuid := (v_entry ->> 'created_by')::uuid;
  v_device_id uuid := (v_audit ->> 'device_id')::uuid;
  v_amount bigint := (v_entry ->> 'amount')::bigint;
  v_method public.payment_method := (v_entry ->> 'payment_method')::public.payment_method;
  v_hash bytea := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  v_existing_hash bytea;
  v_session_cashier uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(v_entry_id::text, 0));
  if public.is_active_owner(v_shop_id) then
    null;
  elsif p_cashier_token is not null then
    v_session_cashier := public.validate_cashier_session(p_cashier_token,v_shop_id,v_device_id);
    if v_session_cashier is null or v_session_cashier <> v_actor_id then
      raise exception 'invalid cashier session' using errcode = '42501';
    end if;
  else
    raise exception 'owner or cashier session required' using errcode = '42501';
  end if;
  if (v_entry ->> 'type') <> 'paymentReceived' or v_amount <= 0 or v_method not in ('cash','digital') then
    raise exception 'invalid customer payment';
  end if;
  if not exists(select 1 from public.devices where id=v_device_id and shop_id=v_shop_id and is_active) then
    raise exception 'active shop device required' using errcode = '42501';
  end if;
  if not exists(select 1 from public.customers where id=v_customer_id and shop_id=v_shop_id and is_active) then
    raise exception 'active customer required';
  end if;
  select operation_hash into v_existing_hash from public.customer_ledger_entries
    where id=v_entry_id and shop_id=v_shop_id;
  if found then
    if v_existing_hash is null or v_existing_hash <> v_hash then
      raise exception 'conflicting replay for immutable customer payment';
    end if;
    return jsonb_build_object('entry_id',v_entry_id,'status','already_synced');
  end if;
  insert into public.customer_ledger_entries(id,shop_id,customer_id,type,amount,payment_reference,
    payment_method,note,created_by,created_at,operation_hash)
  values(v_entry_id,v_shop_id,v_customer_id,'paymentReceived',v_amount,
    nullif(trim(coalesce(v_entry ->> 'payment_reference','')),''),v_method,
    nullif(trim(coalesce(v_entry ->> 'note','')),''),v_actor_id,
    (v_entry ->> 'created_at')::timestamptz,v_hash);
  insert into public.audit_logs(id,shop_id,user_id,action,entity_type,entity_id,new_value,device_id,created_at)
  values((v_audit ->> 'id')::uuid,v_shop_id,v_actor_id,'customer.payment_received',
    'customer_ledger_entry',v_entry_id,v_audit -> 'new_value',v_device_id,
    (v_audit ->> 'created_at')::timestamptz);
  return jsonb_build_object('entry_id',v_entry_id,'status','inserted');
end; $$;

revoke all on function public.save_customer(uuid,uuid,text,text,text,text,bigint,boolean) from public, anon, authenticated;
grant execute on function public.save_customer(uuid,uuid,text,text,text,text,bigint,boolean) to authenticated;
revoke all on function public.sync_customer_payment(jsonb,text) from public, anon, authenticated;
grant execute on function public.sync_customer_payment(jsonb,text) to anon, authenticated;

commit;
