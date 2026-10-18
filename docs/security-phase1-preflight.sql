-- Security Phase 1 — production preflight. READ-ONLY: one SELECT, no writes,
-- no RPC calls. Paste into Supabase Dashboard → SQL Editor and Run; copy the
-- single JSON cell back. Works before migration 202610140001 (uses only
-- columns that already exist). Selects no customer data and no owner email,
-- phone or name; shops are identified by id and shop name only.
with
dev as (
  select d.shop_id, d.device_type::text as device_type, d.is_active, d.last_seen_at,
         d.last_synced_at, d.created_at
    from public.devices d
),
per_shop as (
  select s.id as shop_id, s.name as shop_name, s.created_at,
         count(dev.shop_id) as devices_total,
         count(dev.shop_id) filter (where dev.is_active) as active_total,
         count(dev.shop_id) filter (where dev.is_active and dev.device_type = 'mobile') as active_mobile,
         count(dev.shop_id) filter (where dev.is_active and dev.device_type <> 'mobile') as active_tablet_like,
         count(dev.shop_id) filter (where not dev.is_active) as inactive_will_be_revoked,
         max(dev.last_seen_at) as last_device_seen,
         (select count(*) from public.shop_users u where u.shop_id = s.id and u.role = 'owner' and u.is_active) as active_owners,
         (select count(*) from public.shop_users u where u.shop_id = s.id and u.role <> 'owner' and u.is_active) as other_active_members,
         x.plan_id, x.status::text as sub_status, x.period_end, x.grace_until,
         x.status::text in ('trialing','active','cancelled') as entitlement_issuable,
         coalesce(x.period_end > now(), false) as in_paid_or_trial_period,
         coalesce(x.grace_until > now(), false) as in_offline_grace
    from public.shops s
    left join dev on dev.shop_id = s.id
    left join public.shop_subscriptions x on x.shop_id = s.id
   group by s.id, s.name, s.created_at, x.plan_id, x.status, x.period_end, x.grace_until
)
select jsonb_pretty(jsonb_build_object(
  'migrations_applied_latest', (select jsonb_agg(version order by version desc)
      from (select version from supabase_migrations.schema_migrations order by version desc limit 8) v),
  'shops', (select count(*) from public.shops),
  'devices_registered', (select count(*) from public.devices),
  'devices_active', (select count(*) from public.devices where is_active),
  'devices_by_type', (select jsonb_object_agg(t, n) from (select device_type as t, count(*) as n from dev group by 1) q),
  'per_shop', (select jsonb_agg(to_jsonb(p) order by p.created_at) from per_shop p),
  'shops_over_total_limit', (select coalesce(jsonb_agg(shop_id), '[]') from per_shop where active_total > 2),
  'shops_over_per_type_limit', (select coalesce(jsonb_agg(shop_id), '[]') from per_shop
                                  where active_mobile > 1 or active_tablet_like > 1),
  'shops_with_inactive_devices', (select coalesce(jsonb_agg(shop_id), '[]') from per_shop where inactive_will_be_revoked > 0),
  'shops_not_issuable_DPL03', (select coalesce(jsonb_agg(shop_id), '[]') from per_shop where not entitlement_issuable or sub_status is null),
  'shops_past_offline_grace', (select coalesce(jsonb_agg(shop_id), '[]') from per_shop where not in_offline_grace),
  'shops_without_active_owner', (select coalesce(jsonb_agg(shop_id), '[]') from per_shop where active_owners = 0),
  'ali_shop', (select coalesce(jsonb_agg(to_jsonb(p)), '[]') from per_shop p where p.shop_name ilike '%ali%'),
  'device_credentials_issued', (select count(*) from dukaan_private.device_credentials),
  'cashier_sessions_live', (select count(*) from public.cashier_sessions where revoked_at is null and expires_at > now()),
  'prerequisites', jsonb_build_object(
     'platform_admins_absent', to_regclass('dukaan_private.platform_admins') is null,
     'is_platform_admin_absent', to_regprocedure('public.is_platform_admin()') is null,
     'admin_record_owner_login_created_absent', to_regprocedure('public.admin_record_owner_login_created(uuid)') is null,
     'shops_license_status_absent', not exists(select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'shops' and column_name = 'license_status'),
     'device_credentials_present', to_regclass('dukaan_private.device_credentials') is not null,
     'request_device_present', to_regprocedure('dukaan_private.request_device()') is not null,
     'register_shop_device_overloads', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'register_shop_device'),
     'register_shop_device_expected_sig', to_regprocedure('public.register_shop_device(uuid,text,public.device_type,uuid)') is not null,
     'create_owner_shop_present', to_regprocedure('public.create_owner_shop(text,text,text)') is not null,
     'devices_columns', (select jsonb_agg(column_name order by column_name) from information_schema.columns
        where table_schema = 'public' and table_name = 'devices'
          and column_name in ('last_seen_at','last_synced_at','updated_at','is_active','device_type')),
     'shops_updated_at', exists(select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'shops' and column_name = 'updated_at'),
     'device_entitlements_columns', (select jsonb_agg(column_name order by column_name) from information_schema.columns
        where table_schema = 'public' and table_name = 'device_entitlements' and column_name in ('revoked_at','updated_at','device_id','shop_id')),
     'auth_users_triggers', (select jsonb_agg(tgname order by tgname) from pg_trigger
        where tgrelid = 'auth.users'::regclass and not tgisinternal),
     'customer_ledger_sale_index_exists', to_regclass('public.customer_ledger_entries_sale') is not null,
     'customer_ledger_rows', (select count(*) from public.customer_ledger_entries)
  )
)) as preflight;
