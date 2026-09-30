begin;

create schema if not exists extensions;
alter extension pgcrypto set schema extensions;

alter table public.devices add column updated_at timestamptz not null default now();
alter table public.master_products add column is_active boolean not null default true;
alter table public.sales add column aggregate_hash bytea;

create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin new.updated_at := now(); return new; end; $$;
create trigger shops_touch_updated_at before update on public.shops for each row execute function public.touch_updated_at();
create trigger devices_touch_updated_at before update on public.devices for each row execute function public.touch_updated_at();
create trigger cashiers_touch_updated_at before update on public.cashiers for each row execute function public.touch_updated_at();
create trigger categories_touch_updated_at before update on public.categories for each row execute function public.touch_updated_at();
create trigger master_products_touch_updated_at before update on public.master_products for each row execute function public.touch_updated_at();
create trigger shop_products_touch_updated_at before update on public.shop_products for each row execute function public.touch_updated_at();
create trigger customers_touch_updated_at before update on public.customers for each row execute function public.touch_updated_at();
revoke all on function public.touch_updated_at() from public;

create table public.cashier_sessions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  cashier_id uuid not null,
  device_id uuid not null,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  foreign key(cashier_id, shop_id) references public.cashiers(id, shop_id),
  foreign key(device_id, shop_id) references public.devices(id, shop_id)
);
create index cashier_sessions_context on public.cashier_sessions(shop_id, cashier_id, device_id, expires_at);

create table public.cashier_auth_attempts (
  shop_id uuid not null,
  cashier_id uuid not null,
  device_identifier uuid not null,
  failed_count integer not null default 0,
  blocked_until timestamptz,
  last_attempt_at timestamptz not null default now(),
  primary key(shop_id, cashier_id, device_identifier)
);

alter table public.cashier_sessions enable row level security;
alter table public.cashier_auth_attempts enable row level security;
create policy cashier_sessions_owner_select on public.cashier_sessions for select to authenticated using(public.is_active_owner(shop_id));

create or replace function public.create_cashier(p_shop_id uuid, p_display_name text, p_login_code text, p_pin text)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_id uuid;
begin
  if not public.is_active_owner(p_shop_id) then raise exception 'owner access required' using errcode = '42501'; end if;
  if p_pin !~ '^[0-9]{4,8}$' then raise exception 'PIN must contain 4 to 8 digits'; end if;
  insert into public.cashiers(shop_id, display_name, login_code, pin_hash)
    values(p_shop_id, trim(p_display_name), trim(p_login_code), extensions.crypt(p_pin, extensions.gen_salt('bf', 12))) returning id into v_id;
  return v_id;
end; $$;

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
      on conflict(shop_id, cashier_id, device_identifier) do update set
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
revoke all on function public.authenticate_cashier(uuid,uuid,uuid,text) from public;
grant execute on function public.authenticate_cashier(uuid,uuid,uuid,text) to anon, authenticated;

create or replace function public.validate_cashier_session(p_session_token text, p_shop_id uuid, p_device_id uuid)
returns uuid language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare v_cashier_id uuid;
begin
  update public.cashier_sessions s set last_used_at = now()
    from public.cashiers c, public.devices d
    where s.token_hash = extensions.digest(convert_to(p_session_token, 'UTF8'), 'sha256')
      and s.shop_id = p_shop_id and s.device_id = p_device_id and s.revoked_at is null and s.expires_at > now()
      and c.id = s.cashier_id and c.shop_id = s.shop_id and c.is_active
      and d.id = s.device_id and d.shop_id = s.shop_id and d.is_active
    returning s.cashier_id into v_cashier_id;
  return v_cashier_id;
end; $$;
revoke all on function public.validate_cashier_session(text,uuid,uuid) from public;
grant execute on function public.validate_cashier_session(text,uuid,uuid) to anon, authenticated;

create or replace function public.revoke_cashier_session(p_session_token text)
returns void language sql security definer set search_path = public, extensions, pg_temp as $$
  update public.cashier_sessions set revoked_at = coalesce(revoked_at, now())
    where token_hash = extensions.digest(convert_to(p_session_token, 'UTF8'), 'sha256');
$$;
revoke all on function public.revoke_cashier_session(text) from public;
grant execute on function public.revoke_cashier_session(text) to anon, authenticated;

create or replace function public.revoke_cashier_sessions(p_shop_id uuid, p_cashier_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_active_owner(p_shop_id) then raise exception 'owner access required' using errcode = '42501'; end if;
  update public.cashier_sessions set revoked_at = coalesce(revoked_at, now()) where shop_id = p_shop_id and cashier_id = p_cashier_id;
end; $$;
revoke all on function public.revoke_cashier_sessions(uuid,uuid) from public;
grant execute on function public.revoke_cashier_sessions(uuid,uuid) to authenticated;

create or replace function public.set_cashier_active(p_shop_id uuid, p_cashier_id uuid, p_is_active boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_active_owner(p_shop_id) then raise exception 'owner access required' using errcode = '42501'; end if;
  update public.cashiers set is_active = p_is_active, updated_at = now() where id = p_cashier_id and shop_id = p_shop_id;
  if not found then raise exception 'cashier not found'; end if;
  if not p_is_active then update public.cashier_sessions set revoked_at = coalesce(revoked_at, now()) where shop_id = p_shop_id and cashier_id = p_cashier_id; end if;
end; $$;

commit;
