begin;
select plan(24);

-- U1 columns exist with piece defaults.
select has_column('public','shop_products','sell_mode','selling mode column');
select has_column('public','shop_products','family_id','family column');
select has_column('public','shop_products','measure_presets','quick quantities column');
select has_column('public','shop_products','allow_custom_quantity','custom quantity column');
select has_column('public','sale_items','measure_unit_snapshot','sale-line measure snapshot');
select col_default_is('public','shop_products','sell_mode','piece','existing products are piece products');
select col_not_null('public','shop_products','sell_mode','selling mode is required');

-- Invariants live in the database.
select ok(exists(select 1 from pg_constraint where conname='shop_products_measured_unit'),'measured requires kg or liter');
select ok(exists(select 1 from pg_constraint where conname='shop_products_measure_presets'),'quick quantities are bounded');
select ok(exists(select 1 from pg_constraint where conname='sale_items_measure_unit_snapshot'),'snapshot is kg, liter or null');
select has_index('public','shop_products','shop_products_unique_barcode','barcode unique per shop');
select has_index('public','shop_products','shop_products_family','family lookup index');
select has_trigger('public','shop_products','b10_shop_product_identity','identity guard trigger');
select is((select prosecdef from pg_proc where oid='public.enforce_shop_product_identity()'::regprocedure),true,'identity guard sees every shop');
select is(has_function_privilege('authenticated','public.enforce_shop_product_identity()','EXECUTE'),false,'guard is not client-callable');

-- Selling mode and family change only through the owner RPCs.
select is(has_column_privilege('authenticated','public.shop_products','sell_mode','UPDATE'),false,'no direct sell_mode update');
select is(has_column_privilege('authenticated','public.shop_products','family_id','UPDATE'),false,'no direct family update');
select is(has_column_privilege('authenticated','public.shop_products','measure_presets','UPDATE'),true,'owners tune quick quantities');
select is(has_column_privilege('authenticated','public.shop_products','allow_custom_quantity','UPDATE'),true,'owners toggle custom quantity');
select function_privs_are('public','create_shop_product',array['jsonb'],'authenticated',array['EXECUTE'],'owners create products');
select function_privs_are('public','create_shop_product',array['jsonb'],'anon',array[]::text[],'devices cannot create products');
select function_privs_are('public','set_product_family',array['uuid','uuid','uuid[]'],'authenticated',array['EXECUTE'],'owners group products');
select function_privs_are('public','set_product_family',array['uuid','uuid','uuid[]'],'anon',array[]::text[],'devices cannot group products');

-- The cashier pull keeps its callers.
select function_privs_are('public','device_pull',array['text','bigint','uuid','integer'],'anon',array['EXECUTE'],'device pull unchanged');

select * from finish();
rollback;
