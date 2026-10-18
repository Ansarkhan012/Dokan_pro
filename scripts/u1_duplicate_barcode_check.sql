-- U1 read-only preflight: run BEFORE applying migration
-- 202610080001_product_units_variants.sql to any database (local or hosted).
--
-- It only reads. It lists every shop that has two or more products with the
-- same custom barcode (the migration's per-shop unique index cannot be built
-- over them) and every custom barcode that repeats the barcode of a master
-- product the same shop has added (allowed to stay, but blocked for new
-- writes). An empty first result means the migration's preflight will pass.
-- Nothing is deleted or merged; duplicates are resolved by the owner.
begin transaction read only;

select 'duplicate_custom_barcode' as finding, shop_id, barcode,
       count(*) as products, string_agg(id::text, ',' order by created_at) as product_ids
  from public.shop_products
 where barcode is not null
 group by shop_id, barcode
having count(*) > 1
 order by shop_id, barcode;

select 'custom_barcode_equals_added_master' as finding, c.shop_id, c.barcode,
       c.id as custom_product_id, m.id as master_shop_product_id
  from public.shop_products c
  join public.shop_products m on m.shop_id = c.shop_id and m.id <> c.id and m.barcode is null
  join public.master_products mp on mp.id = m.master_product_id and mp.barcode = c.barcode
 where c.barcode is not null
 order by c.shop_id, c.barcode;

rollback;
