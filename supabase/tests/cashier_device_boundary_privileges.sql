begin;
select plan(34);

-- Device credential storage is private: unexposed schema, no client access.
select has_table('dukaan_private','device_credentials','device credential table exists');
select is((select relrowsecurity from pg_class where oid='dukaan_private.device_credentials'::regclass),true,'device credentials have RLS');
select schema_privs_are('dukaan_private','anon',array[]::text[],'anon has no access to the private schema');
select schema_privs_are('dukaan_private','authenticated',array[]::text[],'authenticated has no access to the private schema');
select table_privs_are('dukaan_private','device_credentials','anon',array[]::text[],'anon cannot touch device credentials');
select table_privs_are('dukaan_private','device_credentials','authenticated',array[]::text[],'authenticated cannot touch device credentials');
select hasnt_column('public','devices','credential_hash','no credential column on the client-readable devices table');

-- Private helpers: SECURITY DEFINER, empty search_path, no client EXECUTE.
select is((select prosecdef and proconfig = array['search_path=""'] from pg_proc where oid='dukaan_private.request_device()'::regprocedure),true,'validator is definer with empty search_path');
select is((select prosecdef and proconfig = array['search_path=""'] from pg_proc where oid='dukaan_private.cashier_operation_authority(uuid,uuid,uuid,timestamptz,text)'::regprocedure),true,'authority is definer with empty search_path');
select function_privs_are('dukaan_private','request_device',array[]::text[],'anon',array[]::text[],'anon cannot call the validator');
select function_privs_are('dukaan_private','request_device',array[]::text[],'authenticated',array[]::text[],'authenticated cannot call the validator');
select function_privs_are('dukaan_private','cashier_operation_authority',array['uuid','uuid','uuid','timestamptz','text'],'anon',array[]::text[],'anon cannot call the authority helper');
select function_privs_are('dukaan_private','shop_owner',array['uuid'],'anon',array[]::text[],'anon cannot resolve the shop owner');
select is(has_function_privilege('public','dukaan_private.request_device()','EXECUTE'),false,'PUBLIC cannot call the validator');

-- Provisioning: owners only.
select function_privs_are('public','issue_device_credential',array['uuid','uuid'],'authenticated',array['EXECUTE'],'owners may provision');
select function_privs_are('public','issue_device_credential',array['uuid','uuid'],'anon',array[]::text[],'anon cannot provision');
select is((select proconfig = array['search_path=""'] from pg_proc where oid='public.issue_device_credential(uuid,uuid)'::regprocedure),true,'provisioning has empty search_path');

-- Device read path: anon (device credential) only.
select function_privs_are('public','device_pull',array['text','bigint','uuid','integer'],'anon',array['EXECUTE'],'device pull for the device credential');
select function_privs_are('public','device_pull',array['text','bigint','uuid','integer'],'authenticated',array[]::text[],'no device pull for JWT sessions');

-- Cashier sync entry points keep their callers; previous versions are internal.
select function_privs_are('public','sync_sale_transaction',array['jsonb','text'],'anon',array['EXECUTE'],'sale sync callable by devices');
select function_privs_are('public','sync_customer_payment',array['jsonb','text'],'anon',array['EXECUTE'],'payment sync callable by devices');
select function_privs_are('public','sync_sale_transaction_coded_legacy',array['jsonb','text'],'anon',array[]::text[],'previous sale sync is internal (anon)');
select function_privs_are('public','sync_sale_transaction_coded_legacy',array['jsonb','text'],'authenticated',array[]::text[],'previous sale sync is internal (authenticated)');
select function_privs_are('public','sync_customer_payment_coded_legacy',array['jsonb','text'],'anon',array[]::text[],'previous payment sync is internal (anon)');
select function_privs_are('public','sync_customer_payment_coded_legacy',array['jsonb','text'],'authenticated',array[]::text[],'previous payment sync is internal (authenticated)');

-- Anon still has no direct table access to tenant data.
select table_privs_are('public','shops','anon',array[]::text[],'anon cannot read shops directly');
select table_privs_are('public','sales','anon',array[]::text[],'anon cannot read sales directly');

-- Grant hygiene: procurement and expense tables are client read-only.
select table_privs_are('public','suppliers','authenticated',array['SELECT'],'suppliers are read-only for owners');
select table_privs_are('public','purchases','authenticated',array['SELECT'],'purchases are read-only for owners');
select table_privs_are('public','purchase_items','anon',array[]::text[],'anon has no purchase item privileges');
select table_privs_are('public','purchase_payments','authenticated',array['SELECT'],'purchase payments are read-only for owners');
select table_privs_are('public','supplier_ledger_entries','authenticated',array['SELECT'],'supplier ledger is read-only for owners');
select table_privs_are('public','expense_categories','anon',array[]::text[],'anon has no expense category privileges');
select table_privs_are('public','expenses','authenticated',array['SELECT'],'expenses are read-only for owners');

select * from finish();
rollback;
