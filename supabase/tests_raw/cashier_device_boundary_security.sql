-- Cashier/owner server boundary: device credential, cashier session proof
-- (live and historical), device read path and procurement grant hygiene.
-- Executable regression test for an isolated local Supabase database.
begin;

-- Shop A: owner, two devices, two cashiers, products and customers.
-- Shop B: owner, one device, one cashier.
insert into auth.users(id, email) values
 ('b1000000-0000-0000-0000-00000000000a','boundary-a@example.test'),
 ('b1000000-0000-0000-0000-00000000000b','boundary-b@example.test');
insert into public.shops(id,name) values
 ('b5000000-0000-0000-0000-00000000000a','Boundary A'),
 ('b5000000-0000-0000-0000-00000000000b','Boundary B');
insert into public.shop_users(shop_id,user_id,role) values
 ('b5000000-0000-0000-0000-00000000000a','b1000000-0000-0000-0000-00000000000a','owner'),
 ('b5000000-0000-0000-0000-00000000000b','b1000000-0000-0000-0000-00000000000b','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier) values
 ('bd000000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000a','A1','androidTablet','be000000-0000-0000-0000-0000000000a1'),
 ('bd000000-0000-0000-0000-0000000000a2','b5000000-0000-0000-0000-00000000000a','A2','androidTablet','be000000-0000-0000-0000-0000000000a2'),
 ('bd000000-0000-0000-0000-0000000000b1','b5000000-0000-0000-0000-00000000000b','B1','androidTablet','be000000-0000-0000-0000-0000000000b1');
insert into public.cashiers(id,shop_id,display_name,login_code,pin_hash) values
 ('bc000000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000a','Ahmed','ahmed',extensions.crypt('1234',extensions.gen_salt('bf',4))),
 ('bc000000-0000-0000-0000-0000000000a2','b5000000-0000-0000-0000-00000000000a','Bilal','bilal',extensions.crypt('5678',extensions.gen_salt('bf',4))),
 ('bc000000-0000-0000-0000-0000000000b1','b5000000-0000-0000-0000-00000000000b','Chand','chand',extensions.crypt('1111',extensions.gen_salt('bf',4)));
insert into public.categories(id,shop_id,name,created_at,updated_at) values
 ('b7000000-0000-0000-0000-00000000000a','b5000000-0000-0000-0000-00000000000a','A',now(),now()),
 ('b7000000-0000-0000-0000-00000000000b','b5000000-0000-0000-0000-00000000000b','B',now(),now());
insert into public.shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,created_at,updated_at) values
 ('b9000000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000a','Coke','b7000000-0000-0000-0000-00000000000a','piece',15000,18000,now(),now()),
 ('b9000000-0000-0000-0000-0000000000b1','b5000000-0000-0000-0000-00000000000b','Tea','b7000000-0000-0000-0000-00000000000b','piece',1000,2000,now(),now());
insert into public.customers(id,shop_id,name,credit_limit,created_at,updated_at) values
 ('bf000000-0000-0000-0000-0000000000a1','b5000000-0000-0000-0000-00000000000a','Udhaar',null,now(),now()),
 ('bf000000-0000-0000-0000-0000000000a2','b5000000-0000-0000-0000-00000000000a','Limited',10000,now(),now());
insert into public.customer_ledger_entries(id,shop_id,customer_id,type,amount,created_by,created_at) values
 (gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a','bf000000-0000-0000-0000-0000000000a1','openingBalance',100000,'b1000000-0000-0000-0000-00000000000a',now());

-- Test helpers (temporary, executed as the calling role).
create function pg_temp.use_device(p_device uuid, p_secret text) returns void language sql as $$
  select set_config('request.headers', json_build_object('x-dukaan-device', p_device::text || '.' || p_secret)::text, true);
$$;
create function pg_temp.no_device() returns void language sql as $$
  select set_config('request.headers', '{}', true);
$$;
create function pg_temp.expect_state(p_sql text, p_state text, p_label text) returns void language plpgsql as $$
declare v_state text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state <> p_state then
      raise exception '%: expected SQLSTATE %, got % (%)', p_label, p_state, v_state, sqlerrm;
    end if;
    return;
  end;
  raise exception '%: expected SQLSTATE %, but it succeeded', p_label, p_state;
end $$;
create function pg_temp.sale(p_id uuid, p_shop uuid, p_device uuid, p_cashier uuid, p_product uuid,
  p_at timestamptz, p_credit_customer uuid default null, p_amount bigint default 18000) returns jsonb language sql as $$
  select jsonb_build_object(
    'version',1,'operation','sync_sale_transaction','audit_id',gen_random_uuid(),
    'sale',jsonb_build_object('id',p_id,'shopId',p_shop,'cashierId',p_cashier,'customerId',p_credit_customer,
      'deviceId',p_device,'invoiceNumber',null,'subtotal',p_amount,'discountTotal',0,'taxTotal',0,
      'grandTotal',p_amount,'paymentStatus','paid','saleStatus','completed','createdAt',p_at),
    'sale_items',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'productId',p_product,
      'productNameSnapshot','Item','barcodeSnapshot',null,'quantity',(p_amount * 1000 / 18000),
      'costPriceSnapshot',15000,'salePriceSnapshot',18000,'discountAmount',0,'lineTotal',p_amount,'createdAt',p_at)),
    'payments',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),
      'paymentMethod',case when p_credit_customer is null then 'cash' else 'credit' end,
      'amount',p_amount,'reference',null,'createdAt',p_at)),
    'inventory_movements',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'productId',p_product,
      'type','sale','quantity',-(p_amount * 1000 / 18000),'createdAt',p_at)),
    'customer_ledger_entries',case when p_credit_customer is null then '[]'::jsonb
      else jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'customerId',p_credit_customer,
        'amount',p_amount,'createdAt',p_at)) end);
$$;
create function pg_temp.payment(p_id uuid, p_shop uuid, p_device uuid, p_cashier uuid, p_at timestamptz)
returns jsonb language sql as $$
  select jsonb_build_object(
    'entry',jsonb_build_object('id',p_id,'shop_id',p_shop,'customer_id','bf000000-0000-0000-0000-0000000000a1',
      'type','paymentReceived','amount',1000,'payment_method','cash','created_by',p_cashier,'created_at',p_at),
    'audit',jsonb_build_object('id',gen_random_uuid(),'device_id',p_device,'created_at',p_at,'new_value','{}'::jsonb));
$$;

-- Row counts read as the test owner (anon cannot count these tables).
create function pg_temp.counts() returns bigint[] language sql security definer as $$
  select array[(select count(*) from public.sales),(select count(*) from public.sale_items),(select count(*) from public.sale_payments),
    (select count(*) from public.inventory_movements),(select count(*) from public.customer_ledger_entries),(select count(*) from public.audit_logs)];
$$;
create temp table secrets(name text primary key, value text);
grant all on secrets to anon, authenticated;

-- PROVISIONING: owner-only, own shop, active device; returns 64 hex chars.
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-00000000000a',true);
insert into secrets values
 ('a1', public.issue_device_credential('b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a1')),
 ('a2', public.issue_device_credential('b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a2'));
select pg_temp.expect_state($$select public.issue_device_credential('b5000000-0000-0000-0000-00000000000b','bd000000-0000-0000-0000-0000000000b1')$$,
  '42501','owner A cannot provision shop B');
select pg_temp.expect_state($$select public.issue_device_credential('b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000b1')$$,
  '42501','owner A cannot provision a device of shop B under shop A');
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-00000000000b',true);
insert into secrets values
 ('b1', public.issue_device_credential('b5000000-0000-0000-0000-00000000000b','bd000000-0000-0000-0000-0000000000b1'));
reset role;
do $$ begin
  if (select count(*) from secrets where value ~ '^[0-9a-f]{64}$') <> 3 then raise exception 'credential is not 256-bit hex'; end if;
  if exists(select 1 from dukaan_private.device_credentials c join secrets s on c.credential_hash = convert_to(s.value,'UTF8'))
    then raise exception 'plaintext credential stored'; end if;
  if (select count(*) from dukaan_private.device_credentials where device_id::text like 'bd000000-%') <> 3
    then raise exception 'credential hash not stored'; end if;
end $$;

-- Cashier Ahmed logs in on A1 (anon, PIN): live session token.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
insert into secrets select 'ahmed', session_token from public.authenticate_cashier(
  'b5000000-0000-0000-0000-00000000000a','be000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1','1234');

-- DEVICE CREDENTIAL: anything without it, or malformed, is refused.
select pg_temp.no_device();
select pg_temp.expect_state($$select public.device_pull('shops')$$,'42501','pull without credential');
select set_config('request.headers','{"x-dukaan-device":"not-a-credential"}',true);
select pg_temp.expect_state($$select public.device_pull('shops')$$,'42501','pull with malformed credential');
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a1', repeat('0',64));
select pg_temp.expect_state($$select public.device_pull('shops')$$,'42501','pull with wrong secret');
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a2', (select value from secrets where name='a1'));
select pg_temp.expect_state($$select public.device_pull('shops')$$,'42501','secret of another device');

-- Own-shop minimum reads pass; other shops never appear; secrets never appear.
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a1', (select value from secrets where name='a1'));
do $$
declare v jsonb; e text;
begin
  v := public.device_pull('shops');
  if jsonb_array_length(v) <> 1 or v->0->>'id' <> 'b5000000-0000-0000-0000-00000000000a' then raise exception 'own shop pull failed: %', v; end if;
  foreach e in array array['devices','cashiers','categories','shopProducts','customers','customerLedgerEntries',
    'inventoryMovements','sales','saleItems','salePayments','saleReturns','saleReturnItems','saleVoids'] loop
    v := public.device_pull(e);
    if exists(select 1 from jsonb_array_elements(v) r where r->>'shop_id' is distinct from 'b5000000-0000-0000-0000-00000000000a')
      then raise exception 'foreign row in % pull', e; end if;
    if exists(select 1 from jsonb_array_elements(v) r
              where r ? 'pin_hash' or r ? 'aggregate_hash' or r ? 'operation_hash' or r ? 'token_hash' or r ? 'credential_hash')
      then raise exception 'secret column in % pull', e; end if;
  end loop;
  if jsonb_array_length(public.device_pull('devices')) <> 2 then raise exception 'shop devices not pulled'; end if;
  v := public.device_pull('cashiers');
  if jsonb_array_length(v) <> 2 or (select array_agg(k order by k) from jsonb_object_keys(v->0) k) <>
     array['created_at','credential_version','display_name','id','is_active','login_code','server_seq','shop_id','updated_at']
    then raise exception 'cashier pull exposes more than login fields: %', v->0; end if;
  if jsonb_array_length(public.device_pull('shopProducts')) <> 1 then raise exception 'product pull failed'; end if;
  begin perform public.device_pull('shopUsers'); raise exception 'unsupported entity accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.device_pull('cashierSessions'); raise exception 'unsupported entity accepted';
  exception when invalid_parameter_value then null; end;
end $$;

-- Owner-only operations fail for the device credential.
select pg_temp.expect_state($$select count(*) from public.shops$$,'42501','direct table read');
select pg_temp.expect_state($$select count(*) from public.cashier_sessions$$,'42501','cashier sessions read');
select pg_temp.expect_state($$select count(*) from public.shop_users$$,'42501','shop users read');
select pg_temp.expect_state($$select count(*) from dukaan_private.device_credentials$$,'42501','credential table read');
select pg_temp.expect_state($$select dukaan_private.request_device()$$,'42501','private validator call');
select pg_temp.expect_state($$select public.owner_report_summary('b5000000-0000-0000-0000-00000000000a',now()-interval '1 day',now())$$,'42501','owner report');
select pg_temp.expect_state($$select public.create_cashier('b5000000-0000-0000-0000-00000000000a','Rogue','rogue','9999')$$,'42501','create cashier');
select pg_temp.expect_state($$select public.set_cashier_active('b5000000-0000-0000-0000-00000000000a','bc000000-0000-0000-0000-0000000000a2',false)$$,'42501','set cashier active');
select pg_temp.expect_state($$select public.revoke_cashier_sessions('b5000000-0000-0000-0000-00000000000a','bc000000-0000-0000-0000-0000000000a2')$$,'42501','revoke all cashier sessions');
select pg_temp.expect_state($$update public.shop_products set sale_price = 1$$,'42501','direct product price write');
select pg_temp.expect_state($$update public.customers set credit_limit = null$$,'42501','direct credit limit write');
select pg_temp.expect_state($$insert into public.customers(id,shop_id,name,created_at,updated_at) values(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a','X',now(),now())$$,'42501','direct customer insert');
select pg_temp.expect_state($$select public.save_customer('b5000000-0000-0000-0000-00000000000a',null,'X',null,null,null,null,true)$$,'42501','save customer');
select pg_temp.expect_state($$select public.sync_inventory_adjustment('{}'::jsonb,null)$$,'42501','inventory adjustment');
select pg_temp.expect_state($$select public.sync_purchase_transaction('{}'::jsonb,null)$$,'42501','purchase');
select pg_temp.expect_state($$select public.sync_supplier_payment('{}'::jsonb,null)$$,'42501','supplier payment');
select pg_temp.expect_state($$select public.sync_expense('{}'::jsonb,null)$$,'42501','expense');
select pg_temp.expect_state($$insert into public.expenses(id) values(gen_random_uuid())$$,'42501','direct expense insert');
select pg_temp.expect_state($$truncate public.purchase_items$$,'42501','truncate purchase items');
select pg_temp.expect_state($$select public.register_shop_device('b5000000-0000-0000-0000-00000000000a','X','androidTablet',gen_random_uuid())$$,'42501','register device');
select pg_temp.expect_state($$update public.devices set is_active = false$$,'42501','device administration');
select pg_temp.expect_state($$select public.issue_device_credential('b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a1')$$,'42501','credential self-provisioning');
select pg_temp.expect_state($$select public.sync_sale_void('{}'::jsonb,null)$$,'42501','void');
select pg_temp.expect_state($$select public.sync_sale_return('{}'::jsonb,null)$$,'42501','return');
select pg_temp.expect_state($$select public.update_shop_settings('b5000000-0000-0000-0000-00000000000a','X','','',true,0,'','80mm',true,true,false)$$,'42501','shop settings');
select pg_temp.expect_state($$select public.entitlement_claims('b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a1')$$,'42501','subscription claims');
select pg_temp.expect_state($$select public.create_owner_shop('Rogue')$$,'42501','create shop');

-- CASHIER: a live session uploads its own sale and payment.
do $$
declare r jsonb;
begin
  r := public.sync_sale_transaction(pg_temp.sale('5b000000-0000-0000-0000-000000000001','b5000000-0000-0000-0000-00000000000a',
    'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now()),
    (select value from secrets where name='ahmed'));
  if r->>'status' <> 'inserted' then raise exception 'live cashier sale failed: %', r; end if;
  r := public.sync_customer_payment(pg_temp.payment('5c000000-0000-0000-0000-000000000001','b5000000-0000-0000-0000-00000000000a',
    'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1',now()),
    (select value from secrets where name='ahmed'));
  if r->>'status' <> 'inserted' then raise exception 'live cashier payment failed: %', r; end if;
  if current_setting('request.jwt.claim.sub', true) <> '' then raise exception 'owner identity leaked after live upload'; end if;
end $$;

-- Impersonation: Ahmed's token cannot attribute work to Bilal (no session).
select pg_temp.expect_state(format($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a2','b9000000-0000-0000-0000-0000000000a1',now()),%L)$$,
  (select value from secrets where name='ahmed')),'42501','sale impersonating another cashier');
select pg_temp.expect_state(format($$select public.sync_customer_payment(pg_temp.payment(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a2',now()),%L)$$,
  (select value from secrets where name='ahmed')),'42501','payment impersonating another cashier');
-- Device credential alone (no session proof) is not cashier authentication.
select pg_temp.expect_state($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a2','b9000000-0000-0000-0000-0000000000a1',now()),null)$$,
  '42501','device credential without a session');

-- Wrong shop / wrong device.
select pg_temp.expect_state($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a2','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now()),null)$$,
  'DPA01','credential of A1 for an A2 sale');
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000b1', (select value from secrets where name='b1'));
select pg_temp.expect_state(format($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now()),%L)$$,
  (select value from secrets where name='ahmed')),'DPA01','shop B credential for a shop A sale');
select pg_temp.no_device();
select pg_temp.expect_state(format($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a2','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now()),%L)$$,
  (select value from secrets where name='ahmed')),'42501','token without credential for another device');

-- HISTORICAL SESSION: make Ahmed's session a past one (09:00-11:00 relative to
-- now: created 3h ago, revoked 1h ago) and give Bilal an expired one.
reset role;
update public.cashier_sessions set created_at = now() - interval '3 hours', last_used_at = now() - interval '3 hours',
  expires_at = now() + interval '9 hours', revoked_at = now() - interval '1 hour'
 where cashier_id = 'bc000000-0000-0000-0000-0000000000a1';
insert into public.cashier_sessions(shop_id,cashier_id,device_id,token_hash,expires_at,created_at,last_used_at) values
 ('b5000000-0000-0000-0000-00000000000a','bc000000-0000-0000-0000-0000000000a2','bd000000-0000-0000-0000-0000000000a1',
  extensions.digest('expired-bilal','sha256'), now() - interval '2 hours', now() - interval '14 hours', now() - interval '14 hours');
create temp table session_before on commit drop as select * from public.cashier_sessions where shop_id = 'b5000000-0000-0000-0000-00000000000a';
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a1', (select value from secrets where name='a1'));

-- The revoked token cannot start new work, with or without the credential.
select pg_temp.expect_state(format($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now()),%L)$$,
  (select value from secrets where name='ahmed')),'42501','revoked token, sale created now');
select pg_temp.no_device();
select pg_temp.expect_state(format($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now() - interval '2 hours'),%L)$$,
  (select value from secrets where name='ahmed')),'42501','revoked token alone cannot use history');
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a1', (select value from secrets where name='a1'));
-- Created after revocation / before the session / after expiry: refused.
select pg_temp.expect_state($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now() - interval '30 minutes'),null)$$,
  '42501','sale created after revocation');
select pg_temp.expect_state($$select public.sync_customer_payment(pg_temp.payment(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1',now() - interval '30 minutes'),null)$$,
  '42501','payment created after revocation');
select pg_temp.expect_state($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now() - interval '4 hours'),null)$$,
  '42501','sale created before the session');
select pg_temp.expect_state($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a2','b9000000-0000-0000-0000-0000000000a1',now() - interval '1 hour'),null)$$,
  '42501','sale created after the session expired');
-- A historical window on another device proves nothing on this one.
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a2', (select value from secrets where name='a2'));
select pg_temp.expect_state($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a2','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now() - interval '2 hours'),null)$$,
  '42501','history of another device');
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a1', (select value from secrets where name='a1'));

-- Legitimate offline work from inside the windows syncs after logout/expiry,
-- through the unchanged R1 chain (replay idempotent, changed replay refused,
-- invalid payload still DPV01, credit limit still record-and-flag).
create temp table offline(p jsonb, q jsonb, flagged jsonb);
grant all on offline to anon;
insert into offline values(
  pg_temp.sale('5b000000-0000-0000-0000-000000000002','b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a1',
    'bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now() - interval '2 hours','bf000000-0000-0000-0000-0000000000a1',36000),
  pg_temp.payment('5c000000-0000-0000-0000-000000000002','b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a1',
    'bc000000-0000-0000-0000-0000000000a1',now() - interval '2 hours'),
  pg_temp.sale('5b000000-0000-0000-0000-000000000003','b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a1',
    'bc000000-0000-0000-0000-0000000000a2','b9000000-0000-0000-0000-0000000000a1',now() - interval '10 hours','bf000000-0000-0000-0000-0000000000a2',18000));
do $$
declare r jsonb; before_counts bigint[]; after_counts bigint[]; p jsonb := (select p from offline); q jsonb := (select q from offline);
begin
  r := public.sync_sale_transaction(p, (select value from secrets where name='ahmed'));
  if r->>'status' <> 'inserted' then raise exception 'historical sale failed: %', r; end if;
  if current_setting('request.jwt.claim.sub', true) <> '' then raise exception 'owner identity leaked after historical upload'; end if;
  r := public.sync_customer_payment(q, null);
  if r->>'status' <> 'inserted' then raise exception 'historical payment failed: %', r; end if;
  before_counts := pg_temp.counts();
  r := public.sync_sale_transaction(p, null);
  if r->>'status' <> 'already_synced' then raise exception 'historical replay not idempotent: %', r; end if;
  r := public.sync_customer_payment(q, null);
  if r->>'status' <> 'already_synced' then raise exception 'historical payment replay not idempotent: %', r; end if;
  after_counts := pg_temp.counts();
  if before_counts <> after_counts then raise exception 'historical replay duplicated rows'; end if;
end $$;
select pg_temp.expect_state($$select public.sync_sale_transaction(jsonb_set((select p from offline),'{sale,invoiceNumber}','"X"'),null)$$,
  'DPC01','changed historical replay');
select pg_temp.expect_state($$select public.sync_sale_transaction(jsonb_set(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a1','b9000000-0000-0000-0000-0000000000a1',now() - interval '2 hours'),
  '{sale,grandTotal}','1'),null)$$,'DPV01','invalid historical payload');
do $$
declare r jsonb := public.sync_sale_transaction((select flagged from offline), null);
begin
  if r->>'status' <> 'accepted_flagged' then raise exception 'credit limit not record-and-flag: %', r; end if;
end $$;

-- Inactive cashier: the historical window no longer authorises.
reset role;
update public.cashiers set is_active = false where id = 'bc000000-0000-0000-0000-0000000000a2';
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.expect_state($$select public.sync_sale_transaction(pg_temp.sale(gen_random_uuid(),'b5000000-0000-0000-0000-00000000000a',
  'bd000000-0000-0000-0000-0000000000a1','bc000000-0000-0000-0000-0000000000a2','b9000000-0000-0000-0000-0000000000a1',now() - interval '10 hours'),null)$$,
  'DPA01','inactive cashier history');

-- Attribution, stock and ledger are the cashier's, never the owner's; the
-- historical proof did not touch the sessions.
reset role;
do $$ begin
  if (select cashier_id from public.sales where id = '5b000000-0000-0000-0000-000000000002') <> 'bc000000-0000-0000-0000-0000000000a1'
    then raise exception 'sale attribution changed'; end if;
  if (select sum(quantity) from public.inventory_movements where reference_id = '5b000000-0000-0000-0000-000000000002') <> -2000
    or (select created_by from public.inventory_movements where reference_id = '5b000000-0000-0000-0000-000000000002' limit 1) <> 'bc000000-0000-0000-0000-0000000000a1'
    then raise exception 'stock movement changed'; end if;
  if (select amount from public.customer_ledger_entries where sale_id = '5b000000-0000-0000-0000-000000000002' and type = 'creditSale') <> 36000
    or (select created_by from public.customer_ledger_entries where id = '5c000000-0000-0000-0000-000000000002') <> 'bc000000-0000-0000-0000-0000000000a1'
    then raise exception 'ledger changed'; end if;
  if (select user_id from public.audit_logs where entity_id = '5c000000-0000-0000-0000-000000000002') <> 'bc000000-0000-0000-0000-0000000000a1'
    then raise exception 'payment audit attributed to the owner'; end if;
  if exists(select * from public.cashier_sessions where shop_id = 'b5000000-0000-0000-0000-00000000000a'
            except select * from session_before)
    then raise exception 'historical proof modified a cashier session'; end if;
  if (select public.validate_cashier_session((select value from secrets where name='ahmed'),
      'b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a1')) is not null
    then raise exception 'historical upload reopened the session'; end if;
end $$;

-- R1.4 cursor: (server_seq, id) order, strictly after the position.
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a1', (select value from secrets where name='a1'));
do $$
declare v jsonb; w jsonb; last jsonb;
begin
  v := public.device_pull('sales');
  if jsonb_array_length(v) < 3 then raise exception 'sales not pulled: %', v; end if;
  if exists(select 1 from jsonb_array_elements(v) with ordinality a(r, i)
            join jsonb_array_elements(v) with ordinality b(r, j) on j = i + 1
            where ((a.r->>'server_seq')::bigint, (a.r->>'id')::uuid) >= ((b.r->>'server_seq')::bigint, (b.r->>'id')::uuid))
    then raise exception 'pull not in (server_seq, id) order'; end if;
  last := v->0;
  w := public.device_pull('sales', (last->>'server_seq')::bigint, (last->>'id')::uuid);
  if jsonb_array_length(w) <> jsonb_array_length(v) - 1 or w->0 <> v->1 then raise exception 'cursor did not resume strictly after'; end if;
  w := public.device_pull('sales', (last->>'server_seq')::bigint, null);
  if exists(select 1 from jsonb_array_elements(w) r where (r->>'server_seq')::bigint <= (last->>'server_seq')::bigint)
    then raise exception 'seq-only cursor returned old rows'; end if;
  if jsonb_array_length(public.device_pull('sales', null, null, 1)) <> 1 then raise exception 'page limit ignored'; end if;
end $$;

-- Rotation and deactivation fail closed.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-00000000000a',true);
insert into secrets values ('a1-rotated', public.issue_device_credential('b5000000-0000-0000-0000-00000000000a','bd000000-0000-0000-0000-0000000000a1'));
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a1', (select value from secrets where name='a1'));
select pg_temp.expect_state($$select public.device_pull('shops')$$,'42501','rotated credential');
select pg_temp.use_device('bd000000-0000-0000-0000-0000000000a1', (select value from secrets where name='a1-rotated'));
select public.device_pull('shops');
reset role;
update public.devices set is_active = false where id = 'bd000000-0000-0000-0000-0000000000a1';
set local role anon;
select pg_temp.expect_state($$select public.device_pull('shops')$$,'42501','inactive device');
select pg_temp.expect_state($$select public.sync_sale_transaction((select p from offline),null)$$,'42501','inactive device upload');

-- Grant hygiene: no client TRUNCATE/DML on procurement and expenses; RLS on.
reset role;
do $$
declare t text; r text;
begin
  foreach t in array array['suppliers','purchases','purchase_items','purchase_payments','supplier_ledger_entries','expense_categories','expenses'] loop
    foreach r in array array['anon','authenticated'] loop
      if has_table_privilege(r, 'public.' || t, 'INSERT') or has_table_privilege(r, 'public.' || t, 'UPDATE')
         or has_table_privilege(r, 'public.' || t, 'DELETE') or has_table_privilege(r, 'public.' || t, 'TRUNCATE')
         or has_table_privilege(r, 'public.' || t, 'TRIGGER') or has_table_privilege(r, 'public.' || t, 'REFERENCES')
        then raise exception '% still has write privileges on %', r, t; end if;
    end loop;
    if has_table_privilege('anon', 'public.' || t, 'SELECT') then raise exception 'anon can read %', t; end if;
    if not has_table_privilege('authenticated', 'public.' || t, 'SELECT') then raise exception 'owner pull lost SELECT on %', t; end if;
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then raise exception 'RLS disabled on %', t; end if;
  end loop;
end $$;
set local role authenticated;
select pg_temp.expect_state($$truncate public.expenses$$,'42501','authenticated truncate expenses');

rollback;
