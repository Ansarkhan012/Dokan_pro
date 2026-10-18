-- Platform administration, shop licensing and the two-device rule.
--
-- Dukaan Pro is sold, not self-served: the platform owner creates every shop,
-- assigns its owner and activates its subscription. This migration moves that
-- authority to the server and away from anything a client can claim.
--
-- 1. Platform administrators. dukaan_private.platform_admins (a schema
--    PostgREST does not expose) is the only source of the role. It is keyed
--    by auth user id, never by email, and has no client grant: an operator
--    adds a row with SQL (see docs/platform-admin.md). public.is_platform_admin()
--    reads it for auth.uid(); every admin_* function checks it first.
--
-- 2. No self-registration. create_owner_shop loses its execute grant and now
--    raises even if called by a definer path. shops/shop_users already had no
--    client INSERT. admin_create_shop is the only way to create a shop.
--
-- 3. Shop licence. shops.license_status: pending (created, not yet sold),
--    active, suspended. Every existing shop becomes active, so no shop
--    already in use is locked out. Entitlements are issued only to active
--    shops (DPL01), so a suspended shop's devices stop billing once their
--    signed offline grace ends, or immediately on their next successful
--    reconnect (the app records the refusal). Sales already made offline still
--    upload: suspension never discards financial records.
--
-- 4. Two devices. devices.form_factor (mobile | tablet) and
--    devices.approval_status (approved | pending | rejected | revoked). A shop
--    holds at most one approved mobile, one approved tablet, two in total.
--    "Approved" holds the slot whether or not the owner has toggled is_active,
--    so switching a device off and registering another never frees a slot:
--    replacement is an admin decision (admin_approve_device with
--    p_replace_device_id). register_shop_device keeps its signature for old
--    APKs; a device beyond the limit is recorded as pending and inactive, so
--    it gets no device credential, no cashier login and no entitlement.
--    Classification limits: the form factor comes from the app's screen-size
--    hint at first registration and the owner can never change it afterwards;
--    the hard server guarantee is the total of two. An admin can correct the
--    classification (admin_set_device_form_factor). Devices that existed
--    before this migration are approved and kept even beyond the limit
--    (legacy_grandfathered); new activations are then pending until an admin
--    revokes one.
--
-- 5. Entitlements on reconnect. entitlement_claims now also requires an
--    approved device and an active shop, and accepts the cashier-mode device
--    credential for its own device, so a tablet that only runs cashier mode
--    still learns about suspension, revocation and renewal when it reconnects.
--
-- 6. Audit. dukaan_private.platform_audit_log records every admin action and
--    every device activation request; admins read it through admin_list_audit.
--
-- Forward-only. No shop, user, sale or device row is deleted.
begin;

-- 1. Platform administrators -------------------------------------------------
create schema if not exists dukaan_private;
revoke all on schema dukaan_private from public, anon, authenticated;

create table dukaan_private.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  note text not null default '',
  created_at timestamptz not null default now()
);
alter table dukaan_private.platform_admins enable row level security;
revoke all on table dukaan_private.platform_admins from public, anon, authenticated;

create table dukaan_private.platform_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid,
  actor_kind text not null check (actor_kind in ('platform_admin','owner','device','system')),
  action text not null,
  shop_id uuid,
  device_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index platform_audit_log_shop on dukaan_private.platform_audit_log(shop_id, created_at desc);
create index platform_audit_log_created on dukaan_private.platform_audit_log(created_at desc);
alter table dukaan_private.platform_audit_log enable row level security;
revoke all on table dukaan_private.platform_audit_log from public, anon, authenticated;

create function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(
    select 1 from dukaan_private.platform_admins a
     where a.user_id = auth.uid() and a.is_active);
$$;
revoke all on function public.is_platform_admin() from public, anon, authenticated;
grant execute on function public.is_platform_admin() to authenticated;

create function dukaan_private.require_platform_admin() returns uuid
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then
    raise exception 'platform administrator required' using errcode = '42501';
  end if;
  return auth.uid();
end $$;
revoke all on function dukaan_private.require_platform_admin() from public, anon, authenticated;

create function dukaan_private.audit(
  p_actor_kind text, p_action text, p_shop_id uuid, p_device_id uuid, p_details jsonb)
returns void language sql volatile security definer set search_path = '' as $$
  insert into dukaan_private.platform_audit_log(actor_user_id, actor_kind, action, shop_id, device_id, details)
  values (auth.uid(), p_actor_kind, p_action, p_shop_id, p_device_id, coalesce(p_details, '{}'::jsonb));
$$;
revoke all on function dukaan_private.audit(text,text,uuid,uuid,jsonb) from public, anon, authenticated;

-- 2. No self-registration ----------------------------------------------------
revoke all on function public.create_owner_shop(text,text,text) from public, anon, authenticated;
create or replace function public.create_owner_shop(p_name text, p_phone text default '', p_address text default '')
returns table(shop_id uuid, shop_name text)
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  raise exception 'DPL00: shops are created by Dokan Pro support' using errcode = '42501';
end $$;
revoke all on function public.create_owner_shop(text,text,text) from public, anon, authenticated;

-- 3. Shop licence ------------------------------------------------------------
alter table public.shops
  add column license_status text not null default 'active'
    check (license_status in ('pending','active','suspended')),
  add column license_changed_at timestamptz,
  add column license_note text not null default '';
-- Every shop that exists now is in use: keep it working.
update public.shops set license_status = 'active', license_changed_at = now();

-- 4. Two devices -------------------------------------------------------------
alter table public.devices
  add column form_factor text check (form_factor in ('mobile','tablet')),
  add column approval_status text not null default 'approved'
    check (approval_status in ('approved','pending','rejected','revoked')),
  add column approval_changed_at timestamptz,
  add column legacy_grandfathered boolean not null default false;
update public.devices
   set form_factor = case device_type when 'mobile' then 'mobile' else 'tablet' end,
       approval_status = case when is_active then 'approved' else 'revoked' end,
       approval_changed_at = now(),
       legacy_grandfathered = true;
alter table public.devices alter column form_factor set not null;
-- Clients read devices but never write the licensing columns.
revoke update on table public.devices from authenticated;
grant update(device_name, is_active, last_seen_at, last_synced_at) on table public.devices to authenticated;
do $$ begin
  if exists(select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'devices' and column_name = 'updated_at') then
    execute 'grant update(updated_at) on table public.devices to authenticated';
  end if;
end $$;

create function dukaan_private.device_form_factor(p_type public.device_type)
returns text language sql immutable set search_path = '' as $$
  select case p_type when 'mobile'::public.device_type then 'mobile' else 'tablet' end;
$$;
revoke all on function dukaan_private.device_form_factor(public.device_type) from public, anon, authenticated;

-- Raises when approving p_device would break the limit. Callers hold the shop
-- row lock. Grandfathered devices still count.
create function dukaan_private.assert_device_slot(p_shop_id uuid, p_device_id uuid, p_form_factor text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_total int; v_same int;
begin
  select count(*), count(*) filter (where d.form_factor = p_form_factor)
    into v_total, v_same
    from public.devices d
   where d.shop_id = p_shop_id and d.approval_status = 'approved' and d.id <> p_device_id;
  if v_same >= 1 then
    raise exception 'DPL04: this shop already has an approved % device', p_form_factor using errcode = '42501';
  end if;
  if v_total >= 2 then
    raise exception 'DPL04: this shop already has two approved devices' using errcode = '42501';
  end if;
end $$;
revoke all on function dukaan_private.assert_device_slot(uuid,uuid,text) from public, anon, authenticated;

-- Clients (anon, authenticated) never insert devices or change licensing
-- columns; the definer functions below run as the table owner and may. The
-- function is deliberately not security definer so current_user is the real
-- caller. For every caller, an active device must be an approved one.
create function dukaan_private.guard_device_licensing() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.form_factor is null then
    new.form_factor := case new.device_type when 'mobile'::public.device_type then 'mobile' else 'tablet' end;
  end if;
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      raise exception 'DPL05: devices are registered through register_shop_device' using errcode = '42501';
    end if;
    if new.form_factor is distinct from old.form_factor
       or new.approval_status is distinct from old.approval_status
       or new.legacy_grandfathered is distinct from old.legacy_grandfathered
       or new.shop_id is distinct from old.shop_id
       or new.device_identifier is distinct from old.device_identifier
       or new.device_type is distinct from old.device_type then
      raise exception 'DPL05: device licensing is managed by Dokan Pro support' using errcode = '42501';
    end if;
  end if;
  if new.is_active and new.approval_status <> 'approved' then
    raise exception 'DPL02: device is not approved' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function dukaan_private.guard_device_licensing() from public, anon, authenticated;
create trigger devices_guard_licensing before insert or update on public.devices
  for each row execute function dukaan_private.guard_device_licensing();

-- Same signature for old APKs; the result gains approval_status.
drop function public.register_shop_device(uuid,text,public.device_type,uuid);
create function public.register_shop_device(
  p_shop_id uuid, p_device_name text, p_device_type public.device_type, p_device_identifier uuid)
returns table(device_id uuid, is_active boolean, approval_status text, form_factor text)
language plpgsql security definer set search_path = '' as $$
declare
  v_shop public.shops;
  v_device public.devices;
  v_form text := dukaan_private.device_form_factor(p_device_type);
  v_status text := 'approved';
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if p_device_identifier is null or length(trim(coalesce(p_device_name, ''))) = 0 then
    raise exception 'device name and identifier required' using errcode = '22023';
  end if;
  select * into v_shop from public.shops s where s.id = p_shop_id for update;
  if v_shop.license_status = 'suspended' then
    raise exception 'DPL01: shop is suspended' using errcode = '42501';
  end if;

  select * into v_device from public.devices d
   where d.shop_id = p_shop_id and d.device_identifier = p_device_identifier;
  if found then
    -- A known device keeps its classification and its decision; only the
    -- label and heartbeat change. Renaming never re-requests approval.
    update public.devices d set device_name = trim(p_device_name), last_seen_at = now()
     where d.id = v_device.id returning * into v_device;
  else
    begin
      perform dukaan_private.assert_device_slot(p_shop_id, '00000000-0000-0000-0000-000000000000', v_form);
    exception when insufficient_privilege then
      v_status := 'pending';
    end;
    insert into public.devices(shop_id, device_name, device_type, device_identifier, last_seen_at,
                               is_active, form_factor, approval_status, approval_changed_at)
    values (p_shop_id, trim(p_device_name), p_device_type, p_device_identifier, now(),
            v_status = 'approved', v_form, v_status, now())
    returning * into v_device;
    perform dukaan_private.audit('owner',
      case v_status when 'approved' then 'device.activated' else 'device.approval_requested' end,
      p_shop_id, v_device.id,
      jsonb_build_object('form_factor', v_form, 'device_name', v_device.device_name,
                         'device_type', p_device_type));
  end if;
  return query select v_device.id, v_device.is_active, v_device.approval_status, v_device.form_factor;
end $$;
revoke all on function public.register_shop_device(uuid,text,public.device_type,uuid) from public, anon, authenticated;
grant execute on function public.register_shop_device(uuid,text,public.device_type,uuid) to authenticated;

-- Device credentials only for approved devices of a non-suspended shop.
create or replace function public.issue_device_credential(p_shop_id uuid, p_device_id uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare v_secret text;
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  if exists(select 1 from public.shops s where s.id = p_shop_id and s.license_status = 'suspended') then
    raise exception 'DPL01: shop is suspended' using errcode = '42501';
  end if;
  if not exists(select 1 from public.devices d
                where d.id = p_device_id and d.shop_id = p_shop_id and d.is_active
                  and d.approval_status = 'approved') then
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

-- 5. Entitlements ------------------------------------------------------------
-- Owner JWT, or the device credential of this exact device (cashier mode).
create or replace function public.entitlement_claims(p_shop_id uuid, p_device_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.shop_subscriptions; d public.devices; v_shop public.shops; v_req record;
  issued timestamptz := clock_timestamp(); eid uuid := gen_random_uuid();
begin
  if not public.is_active_owner(p_shop_id) then
    select * into v_req from dukaan_private.request_device();
    if v_req.shop_id is distinct from p_shop_id or v_req.device_id is distinct from p_device_id then
      raise exception 'owner access required' using errcode = '42501';
    end if;
  end if;
  select * into v_shop from public.shops where id = p_shop_id;
  if not found or v_shop.license_status <> 'active' then
    raise exception 'DPL01: shop is not active (%)', coalesce(v_shop.license_status, 'missing') using errcode = '42501';
  end if;
  select * into d from public.devices where id = p_device_id and shop_id = p_shop_id;
  if not found or d.approval_status <> 'approved' then
    raise exception 'DPL02: device is not approved' using errcode = '42501';
  end if;
  if not d.is_active then
    raise exception 'active device required' using errcode = '42501';
  end if;
  select * into s from public.shop_subscriptions where shop_id = p_shop_id and status in ('trialing','active','cancelled');
  if not found then raise exception 'DPL03: subscription unavailable' using errcode = '42501'; end if;
  return jsonb_build_object('entitlement_version',1,'entitlement_id',eid,'shop_id',p_shop_id,'device_id',p_device_id,
    'subscription_id',s.id,'plan_id',s.plan_id,'issued_at',issued,'valid_until',s.period_end,
    'offline_grace_until',s.grace_until,'server_time',issued);
end $$;
revoke all on function public.entitlement_claims(uuid,uuid) from public, anon, authenticated;
grant execute on function public.entitlement_claims(uuid,uuid) to anon, authenticated;

-- What the owner app shows: licence, subscription and this device's decision.
create function public.owner_activation_status(p_shop_id uuid, p_device_identifier uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_shop public.shops; v_sub public.shop_subscriptions; v_dev public.devices;
begin
  if not public.is_active_owner(p_shop_id) then
    raise exception 'owner access required' using errcode = '42501';
  end if;
  select * into v_shop from public.shops s where s.id = p_shop_id;
  select * into v_sub from public.shop_subscriptions x where x.shop_id = p_shop_id;
  select * into v_dev from public.devices d where d.shop_id = p_shop_id and d.device_identifier = p_device_identifier;
  return jsonb_build_object(
    'license_status', v_shop.license_status,
    'plan_id', v_sub.plan_id,
    'subscription_status', v_sub.status,
    'period_end', v_sub.period_end,
    'grace_until', v_sub.grace_until,
    'device_id', v_dev.id,
    'device_approval_status', v_dev.approval_status,
    'device_form_factor', v_dev.form_factor,
    'device_is_active', v_dev.is_active,
    'server_time', now());
end $$;
revoke all on function public.owner_activation_status(uuid,uuid) from public, anon, authenticated;
grant execute on function public.owner_activation_status(uuid,uuid) to authenticated;

-- New shops start pending; the trial trigger still gives them a subscription
-- row that the admin then renews.

-- 6. Admin operations --------------------------------------------------------
create function public.admin_list_shops()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform dukaan_private.require_platform_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id, 'name', s.name, 'phone', s.phone, 'address', s.address,
      'license_status', s.license_status, 'license_note', s.license_note,
      'license_changed_at', s.license_changed_at, 'created_at', s.created_at,
      'owners', coalesce((select jsonb_agg(jsonb_build_object('user_id', u.id, 'email', u.email, 'is_active', su.is_active))
                            from public.shop_users su join auth.users u on u.id = su.user_id
                           where su.shop_id = s.id and su.role = 'owner'), '[]'::jsonb),
      'plan_id', x.plan_id, 'subscription_status', x.status,
      'period_end', x.period_end, 'grace_until', x.grace_until,
      'approved_devices', (select count(*) from public.devices d where d.shop_id = s.id and d.approval_status = 'approved'),
      'pending_devices', (select count(*) from public.devices d where d.shop_id = s.id and d.approval_status = 'pending'))
      order by s.created_at desc)
      from public.shops s left join public.shop_subscriptions x on x.shop_id = s.id), '[]'::jsonb);
end $$;

create function public.admin_list_plans()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform dukaan_private.require_platform_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'billing_cycle', p.billing_cycle,
      'price_pkr_minor', p.price_pkr_minor, 'offline_grace_days', p.offline_grace_days) order by p.price_pkr_minor)
    from public.subscription_plans p where p.is_active), '[]'::jsonb);
end $$;

-- Links an existing auth account (created by the admin-create-owner function
-- or by the owner's own earlier sign-up) as the shop's owner.
create function public.admin_assign_owner(p_shop_id uuid, p_owner_email text)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare v_user uuid;
begin
  perform dukaan_private.require_platform_admin();
  if not exists(select 1 from public.shops s where s.id = p_shop_id) then
    raise exception 'shop not found' using errcode = 'P0002';
  end if;
  select u.id into v_user from auth.users u where lower(u.email) = lower(trim(p_owner_email));
  if v_user is null then
    raise exception 'DPL06: no account exists for this email; create the owner login first' using errcode = 'P0002';
  end if;
  insert into public.shop_users(shop_id, user_id, role, is_active) values (p_shop_id, v_user, 'owner', true)
  on conflict (shop_id, user_id) do update set role = 'owner', is_active = true;
  perform dukaan_private.audit('platform_admin', 'shop.owner_assigned', p_shop_id, null,
    jsonb_build_object('owner_user_id', v_user, 'owner_email', lower(trim(p_owner_email))));
  return v_user;
end $$;

create function public.admin_create_shop(
  p_name text, p_phone text, p_address text, p_owner_email text)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare v_shop uuid;
begin
  perform dukaan_private.require_platform_admin();
  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'shop name required' using errcode = '22023';
  end if;
  insert into public.shops(name, phone, address, currency, timezone, allow_negative_stock, license_status, license_changed_at)
  values (trim(p_name), coalesce(trim(p_phone), ''), coalesce(trim(p_address), ''), 'PKR', 'Asia/Karachi', true, 'pending', now())
  returning id into v_shop;
  perform dukaan_private.audit('platform_admin', 'shop.created', v_shop, null,
    jsonb_build_object('name', trim(p_name), 'phone', coalesce(trim(p_phone), '')));
  if length(trim(coalesce(p_owner_email, ''))) > 0 then
    perform public.admin_assign_owner(v_shop, p_owner_email);
  end if;
  return v_shop;
end $$;

create function public.admin_set_shop_status(p_shop_id uuid, p_status text, p_note text default '')
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_old text;
begin
  perform dukaan_private.require_platform_admin();
  if p_status not in ('active','suspended') then
    raise exception 'status must be active or suspended' using errcode = '22023';
  end if;
  select s.license_status into v_old from public.shops s where s.id = p_shop_id for update;
  if not found then raise exception 'shop not found' using errcode = 'P0002'; end if;
  update public.shops s set license_status = p_status, license_changed_at = now(),
         license_note = coalesce(p_note, ''), updated_at = now()
   where s.id = p_shop_id;
  if p_status = 'suspended' then
    update public.device_entitlements e set revoked_at = coalesce(e.revoked_at, now()), updated_at = now()
     where e.shop_id = p_shop_id;
  end if;
  perform dukaan_private.audit('platform_admin',
    case p_status when 'active' then 'shop.activated' else 'shop.suspended' end,
    p_shop_id, null, jsonb_build_object('from', v_old, 'note', coalesce(p_note, '')));
end $$;

-- Extends from the later of now and the current end, so renewing early never
-- loses paid days. Grace follows the plan's offline_grace_days.
create function public.admin_renew_subscription(p_shop_id uuid, p_plan_id text, p_months integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_plan public.subscription_plans; v_sub public.shop_subscriptions; v_start timestamptz; v_end timestamptz;
begin
  perform dukaan_private.require_platform_admin();
  if p_months is null or p_months < 1 or p_months > 36 then
    raise exception 'months must be between 1 and 36' using errcode = '22023';
  end if;
  select * into v_plan from public.subscription_plans p where p.id = p_plan_id and p.is_active;
  if not found or v_plan.billing_cycle = 'trial' then
    raise exception 'paid plan required' using errcode = '22023';
  end if;
  select * into v_sub from public.shop_subscriptions x where x.shop_id = p_shop_id for update;
  v_start := greatest(now(), coalesce(v_sub.period_end, now()));
  v_end := v_start + make_interval(months => p_months);
  if v_sub.id is null then
    insert into public.shop_subscriptions(shop_id, plan_id, status, period_start, period_end, grace_until)
    values (p_shop_id, p_plan_id, 'active', now(), v_end, v_end + make_interval(days => v_plan.offline_grace_days))
    returning * into v_sub;
  else
    update public.shop_subscriptions x
       set plan_id = p_plan_id, status = 'active',
           period_start = case when x.period_end < now() then now() else x.period_start end,
           period_end = v_end, grace_until = v_end + make_interval(days => v_plan.offline_grace_days),
           cancel_at_period_end = false, updated_at = now()
     where x.id = v_sub.id returning * into v_sub;
  end if;
  perform dukaan_private.audit('platform_admin', 'subscription.renewed', p_shop_id, null,
    jsonb_build_object('plan_id', p_plan_id, 'months', p_months, 'period_end', v_sub.period_end));
  return jsonb_build_object('plan_id', v_sub.plan_id, 'period_end', v_sub.period_end, 'grace_until', v_sub.grace_until);
end $$;

create function public.admin_list_devices(p_shop_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform dukaan_private.require_platform_admin();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', d.id, 'device_name', d.device_name, 'device_type', d.device_type, 'form_factor', d.form_factor,
      'approval_status', d.approval_status, 'is_active', d.is_active, 'legacy_grandfathered', d.legacy_grandfathered,
      'last_seen_at', d.last_seen_at, 'created_at', d.created_at, 'approval_changed_at', d.approval_changed_at)
      order by d.created_at)
    from public.devices d where d.shop_id = p_shop_id), '[]'::jsonb);
end $$;

create function dukaan_private.revoke_device(p_device_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.devices d set approval_status = 'revoked', is_active = false, approval_changed_at = now()
   where d.id = p_device_id;
  delete from dukaan_private.device_credentials c where c.device_id = p_device_id;
  update public.cashier_sessions s set revoked_at = coalesce(s.revoked_at, now()) where s.device_id = p_device_id;
  update public.device_entitlements e set revoked_at = coalesce(e.revoked_at, now()), updated_at = now()
   where e.device_id = p_device_id;
end $$;
revoke all on function dukaan_private.revoke_device(uuid) from public, anon, authenticated;

-- Approves a pending (or rejected) device. With p_replace_device_id the old
-- device of the same shop is revoked first, in the same transaction.
create function public.admin_approve_device(
  p_device_id uuid, p_replace_device_id uuid default null, p_form_factor text default null)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_dev public.devices; v_old public.devices; v_form text;
begin
  perform dukaan_private.require_platform_admin();
  select * into v_dev from public.devices d where d.id = p_device_id;
  if not found then raise exception 'device not found' using errcode = 'P0002'; end if;
  perform 1 from public.shops s where s.id = v_dev.shop_id for update;
  if v_dev.approval_status = 'approved' then return; end if;
  v_form := coalesce(p_form_factor, v_dev.form_factor);
  if v_form not in ('mobile','tablet') then raise exception 'invalid form factor' using errcode = '22023'; end if;
  if p_replace_device_id is not null then
    select * into v_old from public.devices d where d.id = p_replace_device_id;
    if not found or v_old.shop_id <> v_dev.shop_id or v_old.id = v_dev.id then
      raise exception 'replacement must be another device of the same shop' using errcode = '22023';
    end if;
    perform dukaan_private.revoke_device(v_old.id);
  end if;
  perform dukaan_private.assert_device_slot(v_dev.shop_id, v_dev.id, v_form);
  update public.devices d set approval_status = 'approved', is_active = true, form_factor = v_form,
         approval_changed_at = now()
   where d.id = v_dev.id;
  perform dukaan_private.audit('platform_admin',
    case when p_replace_device_id is null then 'device.approved' else 'device.replaced' end,
    v_dev.shop_id, v_dev.id,
    jsonb_build_object('form_factor', v_form, 'replaced_device_id', p_replace_device_id,
                       'previous_status', v_dev.approval_status));
end $$;

create function public.admin_reject_device(p_device_id uuid, p_note text default '')
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_dev public.devices;
begin
  perform dukaan_private.require_platform_admin();
  select * into v_dev from public.devices d where d.id = p_device_id for update;
  if not found then raise exception 'device not found' using errcode = 'P0002'; end if;
  if v_dev.approval_status <> 'pending' then
    raise exception 'only a pending device can be rejected' using errcode = '22023';
  end if;
  update public.devices d set approval_status = 'rejected', is_active = false, approval_changed_at = now()
   where d.id = p_device_id;
  perform dukaan_private.audit('platform_admin', 'device.rejected', v_dev.shop_id, v_dev.id,
    jsonb_build_object('note', coalesce(p_note, '')));
end $$;

create function public.admin_revoke_device(p_device_id uuid, p_note text default '')
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_dev public.devices;
begin
  perform dukaan_private.require_platform_admin();
  select * into v_dev from public.devices d where d.id = p_device_id for update;
  if not found then raise exception 'device not found' using errcode = 'P0002'; end if;
  perform dukaan_private.revoke_device(p_device_id);
  perform dukaan_private.audit('platform_admin', 'device.revoked', v_dev.shop_id, v_dev.id,
    jsonb_build_object('note', coalesce(p_note, ''), 'previous_status', v_dev.approval_status));
end $$;

create function public.admin_set_device_form_factor(p_device_id uuid, p_form_factor text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_dev public.devices;
begin
  perform dukaan_private.require_platform_admin();
  if p_form_factor not in ('mobile','tablet') then raise exception 'invalid form factor' using errcode = '22023'; end if;
  select * into v_dev from public.devices d where d.id = p_device_id;
  if not found then raise exception 'device not found' using errcode = 'P0002'; end if;
  perform 1 from public.shops s where s.id = v_dev.shop_id for update;
  if v_dev.approval_status = 'approved' and not v_dev.legacy_grandfathered then
    perform dukaan_private.assert_device_slot(v_dev.shop_id, v_dev.id, p_form_factor);
  end if;
  update public.devices d set form_factor = p_form_factor, approval_changed_at = now() where d.id = p_device_id;
  perform dukaan_private.audit('platform_admin', 'device.reclassified', v_dev.shop_id, v_dev.id,
    jsonb_build_object('from', v_dev.form_factor, 'to', p_form_factor));
end $$;

create function public.admin_list_audit(p_shop_id uuid default null, p_limit integer default 200)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform dukaan_private.require_platform_admin();
  return coalesce((select jsonb_agg(row_to_json(x)::jsonb order by x.created_at desc, x.id desc) from (
      select l.id, l.actor_user_id, u.email as actor_email, l.actor_kind, l.action, l.shop_id,
             s.name as shop_name, l.device_id, l.details, l.created_at
        from dukaan_private.platform_audit_log l
        left join auth.users u on u.id = l.actor_user_id
        left join public.shops s on s.id = l.shop_id
       where p_shop_id is null or l.shop_id = p_shop_id
       order by l.created_at desc, l.id desc
       limit least(greatest(coalesce(p_limit, 200), 1), 1000)) x), '[]'::jsonb);
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.admin_list_shops()',
    'public.admin_list_plans()',
    'public.admin_assign_owner(uuid,text)',
    'public.admin_create_shop(text,text,text,text)',
    'public.admin_set_shop_status(uuid,text,text)',
    'public.admin_renew_subscription(uuid,text,integer)',
    'public.admin_list_devices(uuid)',
    'public.admin_approve_device(uuid,uuid,text)',
    'public.admin_reject_device(uuid,text)',
    'public.admin_revoke_device(uuid,text)',
    'public.admin_set_device_form_factor(uuid,text)',
    'public.admin_list_audit(uuid,integer)']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

commit;
