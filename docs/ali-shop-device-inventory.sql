-- Ali_shop device inventory. READ-ONLY: one SELECT, no writes, no RPC.
-- Supabase Dashboard → SQL Editor → Run. One row per device registration.
-- Returns no credential, token, hash, signing key, owner or customer data.
-- Works before and after migration 202610140001 (uses pre-existing columns).
--
-- How to read it: the Samsung tablet that is in use today is the row whose
-- sales, cashier sessions and last_seen/last_synced keep advancing. A
-- reinstall or "clear data" makes a new identifier, which means a new row.
-- install_time_from_identifier is the moment that app install first created
-- its identifier (UUIDv7, in device time), so rows sort by install history.
with shop as (
  select s.id, s.name from public.shops s where s.name ilike '%ali%'
)
select
  shop.name                                             as shop_name,
  left(d.id::text, 8)                                   as device_short_id,
  d.device_name,
  d.device_type::text                                   as device_type,
  d.is_active,
  d.created_at                                          as registered_at,
  d.last_seen_at,
  d.last_synced_at,
  right(d.device_identifier::text, 6)                   as identifier_tail,
  case when substr(d.device_identifier::text, 15, 1) = '7'
       then to_timestamp(('x' || replace(left(d.device_identifier::text, 13), '-', ''))::bit(48)::bigint / 1000.0)
  end                                                   as install_time_from_identifier,
  exists(select 1 from dukaan_private.device_credentials c where c.device_id = d.id) as has_device_credential,
  (select c.issued_at from dukaan_private.device_credentials c where c.device_id = d.id) as credential_issued_at,
  (select count(*) from public.sales x where x.device_id = d.id)                       as sales_count,
  (select min(x.created_at) from public.sales x where x.device_id = d.id)              as first_sale_at,
  (select max(x.created_at) from public.sales x where x.device_id = d.id)              as last_sale_at,
  (select max(x.synced_at) from public.sales x where x.device_id = d.id)               as last_sale_synced_at,
  (select count(*) from public.inventory_movements m where m.device_id = d.id)         as stock_movements,
  (select count(*) from public.cashier_shifts f where f.device_id = d.id)              as cashier_shifts,
  (select count(*) from public.cashier_sessions cs where cs.device_id = d.id)          as cashier_sessions,
  (select max(cs.last_used_at) from public.cashier_sessions cs where cs.device_id = d.id) as cashier_last_used_at,
  (select count(*) from public.cashier_sessions cs where cs.device_id = d.id
      and cs.revoked_at is null and cs.expires_at > now())                             as cashier_sessions_live,
  (select count(*) from public.device_entitlements e where e.device_id = d.id)         as entitlements_recorded,
  (select max(e.issued_at) from public.device_entitlements e where e.device_id = d.id) as last_entitlement_at
from public.devices d
join shop on shop.id = d.shop_id
order by coalesce(d.last_seen_at, d.created_at) desc;
