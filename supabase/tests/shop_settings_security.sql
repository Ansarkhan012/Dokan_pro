begin;
select plan(9);

select has_column('public','shops','default_low_stock_level','default stock threshold exists');
select has_column('public','shops','receipt_footer','receipt footer exists');
select has_column('public','shops','receipt_paper_width','receipt paper width exists');
select has_column('public','shops','receipt_show_phone','receipt phone preference exists');
select has_column('public','shops','receipt_show_address','receipt address preference exists');
select has_column('public','shops','notifications_enabled','notification preference exists');
select has_function('public','update_shop_settings',array['uuid','text','text','text','boolean','bigint','text','text','boolean','boolean','boolean'],'settings RPC exists');
select function_privs_are('public','update_shop_settings',array['uuid','text','text','text','boolean','bigint','text','text','boolean','boolean','boolean'],'authenticated',array['EXECUTE'],'authenticated can invoke owner-checked settings RPC');
select function_privs_are('public','update_shop_settings',array['uuid','text','text','text','boolean','bigint','text','text','boolean','boolean','boolean'],'anon',array[]::text[],'anon cannot invoke settings RPC');

select * from finish();
rollback;
