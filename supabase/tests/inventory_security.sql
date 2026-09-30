begin;
select plan(7);

select has_function('public','sync_inventory_adjustment',array['jsonb','text'],'inventory sync rpc exists');
select function_privs_are('public','sync_inventory_adjustment',array['jsonb','text'],'authenticated',array['EXECUTE'],'authenticated can execute inventory rpc');
select function_privs_are('public','sync_inventory_adjustment',array['jsonb','text'],'anon',array[]::text[],'anon cannot execute inventory rpc');
select is((select relrowsecurity from pg_class where oid='public.inventory_movements'::regclass),true,'inventory movements has RLS');
select table_privs_are('public','inventory_movements','authenticated',array['SELECT'],'immutable inventory history is select-only');
select isnt((select proconfig::text from pg_proc where oid='public.sync_inventory_adjustment(jsonb,text)'::regprocedure),null,'security definer has fixed configuration');
select ok(position('search_path=public, extensions, pg_temp' in (select array_to_string(proconfig,',') from pg_proc where oid='public.sync_inventory_adjustment(jsonb,text)'::regprocedure))>0,'rpc fixes search_path');

select * from finish();
rollback;
