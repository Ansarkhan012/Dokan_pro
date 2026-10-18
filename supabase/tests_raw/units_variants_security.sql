-- U1 product units and variants: selling-mode immutability, family isolation,
-- per-shop barcodes and the product RPC boundary under RLS.
begin;

insert into auth.users(id,email) values
 ('51000000-0000-0000-0000-000000000001','units-owner-a@example.test'),
 ('52000000-0000-0000-0000-000000000002','units-owner-b@example.test');
insert into public.shops(id,name) values
 ('5a000000-0000-0000-0000-000000000001','Units Shop A'),
 ('5b000000-0000-0000-0000-000000000002','Units Shop B');
insert into public.shop_users(shop_id,user_id,role) values
 ('5a000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001','owner'),
 ('5b000000-0000-0000-0000-000000000002','52000000-0000-0000-0000-000000000002','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier) values
 ('5d000000-0000-0000-0000-000000000001','5a000000-0000-0000-0000-000000000001','A','androidTablet','5e000000-0000-0000-0000-000000000001'),
 ('5d000000-0000-0000-0000-000000000002','5b000000-0000-0000-0000-000000000002','B','androidTablet','5e000000-0000-0000-0000-000000000002');
insert into public.categories(id,shop_id,name,is_active,created_at,updated_at) values
 ('5c000000-0000-0000-0000-000000000001',null,'Units Staples',true,now(),now());

set local role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true);

do $$
declare r jsonb;
begin
  -- Loose atta, Rs 130/kg, 40 kg, and two Tapal sizes in one family.
  r := public.create_shop_product(jsonb_build_object(
    'shop_id','5a000000-0000-0000-0000-000000000001','device_id','5d000000-0000-0000-0000-000000000001',
    'product_id','61000000-0000-0000-0000-000000000001','movement_id','62000000-0000-0000-0000-000000000001',
    'category_id','5c000000-0000-0000-0000-000000000001','name','Atta','unit','kg','sell_mode','measured',
    'purchase_price',12000,'sale_price',13000,'opening_quantity',40000,'measure_presets',jsonb_build_array(250,500,1000,2000,5000)));
  if r->>'status' <> 'inserted' then raise exception 'measured create failed: %', r; end if;
  foreach r in array array[
    jsonb_build_object('product_id','61000000-0000-0000-0000-000000000002','movement_id','62000000-0000-0000-0000-000000000002','pack_label','250 g','barcode','UNITS-TAPAL-250'),
    jsonb_build_object('product_id','61000000-0000-0000-0000-000000000003','movement_id','62000000-0000-0000-0000-000000000003','pack_label','500 g','barcode','UNITS-TAPAL-500')] loop
    perform public.create_shop_product(r || jsonb_build_object(
      'shop_id','5a000000-0000-0000-0000-000000000001','device_id','5d000000-0000-0000-0000-000000000001',
      'category_id','5c000000-0000-0000-0000-000000000001','name','Tapal Danedar','unit','pack',
      'purchase_price',38000,'sale_price',41000,'opening_quantity',12000,'family_id','63000000-0000-0000-0000-000000000001'));
  end loop;
  if (select count(*) from public.shop_products where family_id='63000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'family not created';
  end if;
  if (select sum(quantity) from public.inventory_movements where product_id='61000000-0000-0000-0000-000000000001') <> 40000 then
    raise exception 'measured opening stock not in grams';
  end if;

  -- Selling mode is fixed; direct writes cannot change it or the family.
  begin
    update public.shop_products set sell_mode='piece' where id='61000000-0000-0000-0000-000000000001';
    raise exception 'sell_mode updated directly';
  exception when insufficient_privilege then null; end;
  begin
    update public.shop_products set family_id=null where id='61000000-0000-0000-0000-000000000002';
    raise exception 'family updated directly';
  exception when insufficient_privilege then null; end;
  begin
    update public.shop_products set unit='liter' where id='61000000-0000-0000-0000-000000000001';
    raise exception 'measured unit changed';
  exception when invalid_parameter_value then null; end;

  -- Same barcode twice in one shop is refused.
  begin
    perform public.create_shop_product(jsonb_build_object(
      'shop_id','5a000000-0000-0000-0000-000000000001','device_id','5d000000-0000-0000-0000-000000000001',
      'product_id',gen_random_uuid(),'movement_id',gen_random_uuid(),'category_id','5c000000-0000-0000-0000-000000000001',
      'name','Fake Tapal','unit','pack','purchase_price',1,'sale_price',1,'barcode','UNITS-TAPAL-250'));
    raise exception 'duplicate barcode accepted';
  exception when unique_violation then null; end;

  -- Shop A cannot reach shop B through the RPCs.
  begin
    perform public.set_product_family('5b000000-0000-0000-0000-000000000002','63000000-0000-0000-0000-000000000001',
      array['61000000-0000-0000-0000-000000000002']::uuid[]);
    raise exception 'cross-shop grouping succeeded';
  exception when insufficient_privilege then null; end;
end $$;

-- Owner B: cannot join A's family, may reuse A's barcode in its own shop.
select set_config('request.jwt.claim.sub','52000000-0000-0000-0000-000000000002',true);
do $$ begin
  begin
    perform public.create_shop_product(jsonb_build_object(
      'shop_id','5b000000-0000-0000-0000-000000000002','device_id','5d000000-0000-0000-0000-000000000002',
      'product_id',gen_random_uuid(),'movement_id',gen_random_uuid(),'category_id','5c000000-0000-0000-0000-000000000001',
      'name','Tapal','unit','pack','purchase_price',1,'sale_price',1,'family_id','63000000-0000-0000-0000-000000000001'));
    raise exception 'cross-shop family accepted';
  exception when insufficient_privilege then null; end;
  perform public.create_shop_product(jsonb_build_object(
    'shop_id','5b000000-0000-0000-0000-000000000002','device_id','5d000000-0000-0000-0000-000000000002',
    'product_id',gen_random_uuid(),'movement_id',gen_random_uuid(),'category_id','5c000000-0000-0000-0000-000000000001',
    'name','Tapal B','unit','pack','purchase_price',1,'sale_price',1,'barcode','UNITS-TAPAL-250'));
  if exists(select 1 from public.shop_products where shop_id='5a000000-0000-0000-0000-000000000001') then
    raise exception 'owner B sees shop A products';
  end if;
end $$;

-- Devices (anon) cannot create or group products.
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  begin
    perform public.create_shop_product('{}'::jsonb);
    raise exception 'anonymous create succeeded';
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_product_family('5a000000-0000-0000-0000-000000000001',null,array[]::uuid[]);
    raise exception 'anonymous grouping succeeded';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
