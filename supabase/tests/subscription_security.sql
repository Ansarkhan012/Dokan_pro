begin;
select plan(13);
select has_table('public','subscription_plans','plans table exists');
select has_table('public','shop_subscriptions','subscriptions table exists');
select has_table('public','device_entitlements','entitlements table exists');
select is((select relrowsecurity from pg_class where oid='public.subscription_plans'::regclass),true,'plans RLS enabled');
select is((select relrowsecurity from pg_class where oid='public.shop_subscriptions'::regclass),true,'subscriptions RLS enabled');
select is((select relrowsecurity from pg_class where oid='public.device_entitlements'::regclass),true,'entitlements RLS enabled');
select table_privs_are('public','shop_subscriptions','authenticated',array['SELECT'],'subscriptions are client read-only');
select table_privs_are('public','device_entitlements','authenticated',array['SELECT'],'entitlements are client read-only');
select function_privs_are('public','entitlement_claims',array['uuid','uuid'],'authenticated',array['EXECUTE'],'authenticated may request authorized claims');
-- Since 202610140001 cashier mode (anon + device credential) may request the
-- claims of its own device; without a valid credential the call is refused.
select function_privs_are('public','entitlement_claims',array['uuid','uuid'],'anon',array['EXECUTE'],'anon may call claims, gated by device credential');
set local role anon;
select set_config('request.headers','{}',true);
select throws_ok($$select public.entitlement_claims(gen_random_uuid(),gen_random_uuid())$$,'42501',null,'anon without device credential is refused');
reset role;
select ok(position('search_path=public, pg_temp' in (select array_to_string(proconfig,',') from pg_proc where oid='public.entitlement_claims(uuid,uuid)'::regprocedure))>0,'claims RPC fixes search_path');
select is((select count(*)::integer from public.subscription_plans),5,'five configured plan/cycle records');
select * from finish();
rollback;
