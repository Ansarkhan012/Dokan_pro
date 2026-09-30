-- Local-development helper. Run as the local database administrator after
-- creating test shops. It attaches the stable seed catalog to every current
-- shop (including the active test shop) and creates one idempotent opening-stock
-- movement per product. Stable derived UUIDs make the helper safe to rerun.
begin;

insert into public.shop_products(
  id, shop_id, master_product_id, purchase_price, sale_price,
  stock_tracking_enabled, low_stock_level, is_active, created_at, updated_at
)
select
  md5(s.id::text || ':' || p.slug)::uuid,
  s.id,
  p.master_id,
  p.purchase_price,
  p.sale_price,
  true,
  5000,
  true,
  now(),
  now()
from public.shops s
cross join (values
  ('surf',  'd1000000-0000-0000-0000-000000000001'::uuid, 85000::bigint, 95000::bigint, 20000::bigint),
  ('sugar', 'd1000000-0000-0000-0000-000000000002'::uuid, 16000::bigint, 18000::bigint, 20000::bigint),
  ('milk',  'd1000000-0000-0000-0000-000000000003'::uuid, 25000::bigint, 28000::bigint, 20000::bigint),
  ('rice',  'd1000000-0000-0000-0000-000000000004'::uuid, 30000::bigint, 34000::bigint, 25000::bigint),
  ('oil',   'd1000000-0000-0000-0000-000000000005'::uuid, 52000::bigint, 56000::bigint, 15000::bigint),
  ('tea',   'd1000000-0000-0000-0000-000000000006'::uuid, 43000::bigint, 47000::bigint, 18000::bigint),
  ('salt',  'd1000000-0000-0000-0000-000000000007'::uuid,  9000::bigint, 11000::bigint, 30000::bigint),
  ('biscuit','d1000000-0000-0000-0000-000000000008'::uuid,  7000::bigint,  9000::bigint, 40000::bigint),
  ('drink', 'd1000000-0000-0000-0000-000000000009'::uuid, 16000::bigint, 19000::bigint, 24000::bigint),
  ('atta',  'd1000000-0000-0000-0000-000000000010'::uuid, 65000::bigint, 72000::bigint, 12000::bigint)
) as p(slug, master_id, purchase_price, sale_price, opening_quantity)
on conflict(id) do update set
  master_product_id=excluded.master_product_id,
  purchase_price=excluded.purchase_price,
  sale_price=excluded.sale_price,
  stock_tracking_enabled=true,
  low_stock_level=excluded.low_stock_level,
  is_active=true,
  updated_at=now();

insert into public.inventory_movements(
  id, shop_id, product_id, type, quantity, reference_type, note,
  created_by, created_at
)
select
  md5(s.id::text || ':' || p.slug || ':opening')::uuid,
  s.id,
  md5(s.id::text || ':' || p.slug)::uuid,
  'openingStock'::public.inventory_movement_type,
  p.opening_quantity,
  'development_seed',
  'Development-only opening stock',
  owner.user_id,
  now()
from public.shops s
join lateral (
  select su.user_id
  from public.shop_users su
  where su.shop_id=s.id and su.role='owner' and su.is_active
  order by su.created_at
  limit 1
) owner on true
cross join (values
  ('surf', 20000::bigint),
  ('sugar', 20000::bigint),
  ('milk', 20000::bigint),
  ('rice', 25000::bigint),
  ('oil', 15000::bigint),
  ('tea', 18000::bigint),
  ('salt', 30000::bigint),
  ('biscuit', 40000::bigint),
  ('drink', 24000::bigint),
  ('atta', 12000::bigint)
) as p(slug, opening_quantity)
on conflict(id) do nothing;

commit;
