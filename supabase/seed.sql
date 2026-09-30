-- Global development catalog fixtures. Shop-specific assignments and opening
-- stock are applied explicitly with dev/seed_pos_catalog.sql after a test shop
-- exists. These stable UUIDs make repeated local resets deterministic.
insert into public.categories(id, shop_id, name, is_active, created_at, updated_at)
values
  ('d0000000-0000-0000-0000-000000000001', null, 'Household', true, now(), now()),
  ('d0000000-0000-0000-0000-000000000002', null, 'Staples', true, now(), now()),
  ('d0000000-0000-0000-0000-000000000003', null, 'Dairy', true, now(), now()),
  ('d0000000-0000-0000-0000-000000000004', null, 'Cooking Essentials', true, now(), now()),
  ('d0000000-0000-0000-0000-000000000005', null, 'Beverages', true, now(), now()),
  ('d0000000-0000-0000-0000-000000000006', null, 'Snacks', true, now(), now())
on conflict(id) do update set name=excluded.name, is_active=true, updated_at=now();

insert into public.master_products(
  id, barcode, name, brand, category_id, default_unit, is_active, created_at, updated_at
)
values
  ('d1000000-0000-0000-0000-000000000001','8964001000011','Surf Excel 1kg','Surf Excel','d0000000-0000-0000-0000-000000000001','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000002','8964001000028','Sugar / Cheeni 1kg','','d0000000-0000-0000-0000-000000000002','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000003','8964001000035','Milk 1L','','d0000000-0000-0000-0000-000000000003','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000004','8964001000042','Basmati Rice 1kg','','d0000000-0000-0000-0000-000000000002','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000005','8964001000059','Cooking Oil 1L','','d0000000-0000-0000-0000-000000000004','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000006','8964001000066','Tea 190g','','d0000000-0000-0000-0000-000000000005','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000007','8964001000073','Salt 800g','','d0000000-0000-0000-0000-000000000002','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000008','8964001000080','Biscuits Pack','','d0000000-0000-0000-0000-000000000006','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000009','8964001000097','Soft Drink 1.5L','','d0000000-0000-0000-0000-000000000005','unit',true,now(),now()),
  ('d1000000-0000-0000-0000-000000000010','8964001000103','Atta 5kg','','d0000000-0000-0000-0000-000000000002','unit',true,now(),now())
on conflict(id) do update set
  barcode=excluded.barcode, name=excluded.name, brand=excluded.brand,
  category_id=excluded.category_id, default_unit=excluded.default_unit,
  is_active=true, updated_at=now();

-- Catalog-only candidate used to exercise "Add to My Shop". It is
-- intentionally not included in dev/seed_pos_catalog.sql.
insert into public.master_products(
  id, barcode, name, brand, category_id, default_unit, pack_label,
  is_active, created_at, updated_at
)
values (
  'd1000000-0000-0000-0000-000000000011', '8964001000110',
  'Dishwashing Bar 200g', 'Lemon Max',
  'd0000000-0000-0000-0000-000000000001', 'piece', '200 g',
  true, now(), now()
)
on conflict(id) do update set
  barcode=excluded.barcode, name=excluded.name, brand=excluded.brand,
  category_id=excluded.category_id, default_unit=excluded.default_unit,
  pack_label=excluded.pack_label, is_active=true, updated_at=now();
