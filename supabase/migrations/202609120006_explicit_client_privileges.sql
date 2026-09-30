begin;

grant usage on schema public to anon, authenticated;

-- Supabase's API roles may inherit broad defaults in local or hosted projects.
-- Establish a deny-by-default baseline before adding the client contract below.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

-- PostgreSQL 17 treats the existing ON CONFLICT(shop_id, ...) names as
-- ambiguous with this table-returning function's output variables. Preserve
-- the function contract and target the primary-key constraint explicitly.
create or replace function public.authenticate_cashier(p_shop_id uuid, p_device_identifier uuid, p_cashier_id uuid, p_pin text)
returns table(session_token text, shop_id uuid, cashier_id uuid, device_id uuid, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_device public.devices;
  v_cashier public.cashiers;
  v_attempt public.cashier_auth_attempts;
  v_token text;
  v_expiry timestamptz := now() + interval '12 hours';
begin
  select * into v_device from public.devices d where d.shop_id = p_shop_id and d.device_identifier = p_device_identifier and d.is_active;
  if not found then return; end if;
  select * into v_cashier from public.cashiers c where c.id = p_cashier_id and c.shop_id = p_shop_id and c.is_active;
  if not found then return; end if;
  select * into v_attempt from public.cashier_auth_attempts a
    where a.shop_id = p_shop_id and a.cashier_id = p_cashier_id and a.device_identifier = p_device_identifier for update;
  if found and v_attempt.blocked_until > now() then return; end if;
  if v_cashier.pin_hash <> extensions.crypt(p_pin, v_cashier.pin_hash) then
    insert into public.cashier_auth_attempts(shop_id, cashier_id, device_identifier, failed_count, blocked_until, last_attempt_at)
      values(p_shop_id, p_cashier_id, p_device_identifier, 1, null, now())
      on conflict on constraint cashier_auth_attempts_pkey do update set
        failed_count = public.cashier_auth_attempts.failed_count + 1,
        blocked_until = case when public.cashier_auth_attempts.failed_count + 1 >= 5 then now() + interval '15 minutes' else null end,
        last_attempt_at = now();
    return;
  end if;
  delete from public.cashier_auth_attempts a where a.shop_id = p_shop_id and a.cashier_id = p_cashier_id and a.device_identifier = p_device_identifier;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.cashier_sessions(shop_id, cashier_id, device_id, token_hash, expires_at)
    values(p_shop_id, p_cashier_id, v_device.id, extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), v_expiry);
  return query select v_token, p_shop_id, p_cashier_id, v_device.id, v_expiry;
end; $$;

-- Owner/account bootstrap reads. Profile edits are limited to user-facing data.
grant select on table public.profiles to authenticated;
grant update(full_name, phone, updated_at) on table public.profiles to authenticated;
grant select on table public.shops to authenticated;
grant select on table public.shop_users to authenticated;

-- Cashier credentials and auth-attempt state are never client-readable.
revoke all on table public.cashiers, public.cashier_auth_attempts from anon, authenticated;
grant select(id, shop_id, display_name, login_code, credential_version, is_active, created_at, updated_at)
  on table public.cashiers to authenticated;
revoke all on table public.cashier_sessions from anon, authenticated;
grant select(id, shop_id, cashier_id, device_id, expires_at, revoked_at, created_at, last_used_at)
  on table public.cashier_sessions to authenticated;

-- Registered devices are created by RPC. Owners may rename/revoke/update sync metadata.
grant select on table public.devices to authenticated;
grant update(device_name, is_active, last_seen_at, last_synced_at, updated_at)
  on table public.devices to authenticated;

-- Mutable owner-managed reference data. RLS still restricts every tenant row.
grant select, insert on table public.categories to authenticated;
grant update(name, is_active, updated_at) on table public.categories to authenticated;
grant select on table public.master_products to authenticated;
grant select, insert on table public.shop_products to authenticated;
grant update(master_product_id, custom_name, barcode, purchase_price, sale_price,
  stock_tracking_enabled, low_stock_level, is_active, updated_at)
  on table public.shop_products to authenticated;
grant select, insert on table public.customers to authenticated;
grant update(name, phone, address, credit_limit, is_active, updated_at)
  on table public.customers to authenticated;

-- Shift lifecycle is mutable in Phase 1/2A, but remains tenant-scoped by RLS.
grant select, insert on table public.cashier_shifts to authenticated;
grant update(closed_at, expected_cash, actual_cash, cash_difference, status)
  on table public.cashier_shifts to authenticated;

-- Immutable financial history is readable by owners only through RLS. No direct
-- INSERT/UPDATE/DELETE privileges are granted; approved RPCs perform writes.
grant select on table public.sales to authenticated;
grant select on table public.sale_items to authenticated;
grant select on table public.sale_payments to authenticated;
grant select on table public.inventory_movements to authenticated;
grant select on table public.customer_ledger_entries to authenticated;
grant select on table public.audit_logs to authenticated;

-- No migration uses client-consumed sequences (UUIDs are generated directly).
-- Only these reviewed RPC entry points are callable by clients. Trigger and RLS
-- helper functions intentionally receive no client EXECUTE privilege.
grant execute on function public.is_active_owner(uuid) to authenticated;
grant execute on function public.create_owner_shop(text,text,text) to authenticated;
grant execute on function public.register_shop_device(uuid,text,public.device_type,uuid) to authenticated;
grant execute on function public.create_cashier(uuid,text,text,text) to authenticated;
grant execute on function public.set_cashier_active(uuid,uuid,boolean) to authenticated;
grant execute on function public.authenticate_cashier(uuid,uuid,uuid,text) to anon, authenticated;
grant execute on function public.validate_cashier_session(text,uuid,uuid) to anon, authenticated;
grant execute on function public.revoke_cashier_session(text) to anon, authenticated;
grant execute on function public.revoke_cashier_sessions(uuid,uuid) to authenticated;
grant execute on function public.sync_sale_transaction(jsonb,text) to anon, authenticated;

commit;
