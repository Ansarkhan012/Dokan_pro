-- Executable regression test for an isolated local Supabase database.
begin;

insert into auth.users(id, email) values
 ('11000000-0000-0000-0000-000000000001','a2@example.test'),
 ('22000000-0000-0000-0000-000000000002','b2@example.test');
insert into public.shops(id,name) values
 ('aa000000-0000-0000-0000-000000000001','A2'),
 ('bb000000-0000-0000-0000-000000000002','B2');
insert into public.shop_users(shop_id,user_id,role) values
 ('aa000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000001','owner'),
 ('bb000000-0000-0000-0000-000000000002','22000000-0000-0000-0000-000000000002','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier) values
 ('dd000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','Counter','windowsDesktop','de000000-0000-0000-0000-000000000001');
insert into public.categories(id,shop_id,name,created_at,updated_at) values
 ('ca000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','Test',now(),now());
insert into public.shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,created_at,updated_at) values
 ('cc000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','Coke','ca000000-0000-0000-0000-000000000001','piece',15000,18000,now(),now()),
 ('cc000000-0000-0000-0000-000000000002','aa000000-0000-0000-0000-000000000001','Milk','ca000000-0000-0000-0000-000000000001','liter',20000,25000,now(),now());
insert into public.customers(id,shop_id,name,created_at,updated_at) values
 ('ce000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000001','Ahmed',now(),now());

set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000001',true);

do $$ begin
  if (select count(*) from public.shops) <> 1 then raise exception 'owner A read isolation failed'; end if;
  begin insert into public.shop_users(shop_id,user_id,role) values('bb000000-0000-0000-0000-000000000002',auth.uid(),'owner'); raise exception 'membership escalation succeeded';
  exception when insufficient_privilege then null; end;
  begin update public.shop_users set is_active=false where shop_id='bb000000-0000-0000-0000-000000000002'; raise exception 'membership mutation succeeded';
  exception when insufficient_privilege then null; end;
  begin insert into public.sales(id,shop_id,cashier_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at)
    values(gen_random_uuid(),'aa000000-0000-0000-0000-000000000001',auth.uid(),'dd000000-0000-0000-0000-000000000001',0,0,0,0,'paid','completed',now());
    raise exception 'direct financial insert succeeded'; exception when insufficient_privilege then null; end;
end $$;

do $$ declare t text; begin
  if has_table_privilege('authenticated','public.shop_users','INSERT')
     or has_table_privilege('authenticated','public.shop_users','UPDATE')
     or has_table_privilege('authenticated','public.shop_users','DELETE') then
    raise exception 'membership mutation privilege leaked';
  end if;
  foreach t in array array['sales','sale_items','sale_payments','inventory_movements','customer_ledger_entries','audit_logs'] loop
    if has_table_privilege('authenticated', 'public.' || t, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || t, 'DELETE') then
      raise exception 'immutable financial privilege leaked on %', t;
    end if;
  end loop;
end $$;

select set_config('request.jwt.claim.sub','22000000-0000-0000-0000-000000000002',true);
do $$ begin
  if exists(select 1 from public.shops where id='aa000000-0000-0000-0000-000000000001') then raise exception 'owner B read shop A'; end if;
end $$;
select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000001',true);

do $$
declare c uuid; token text; sid uuid; cid uuid; did uuid; expiry timestamptz; i integer;
begin
  c := public.create_cashier('aa000000-0000-0000-0000-000000000001','Bilal','bilal','1234');
  select * into token,sid,cid,did,expiry from public.authenticate_cashier('aa000000-0000-0000-0000-000000000001','de000000-0000-0000-0000-000000000001',c,'1234');
  if token is null or public.validate_cashier_session(token,sid,did) <> c then raise exception 'correct cashier PIN/session failed'; end if;
  if public.validate_cashier_session(token,'bb000000-0000-0000-0000-000000000002',did) is not null then raise exception 'session escaped shop'; end if;
  if public.validate_cashier_session(token,sid,gen_random_uuid()) is not null then raise exception 'session escaped device'; end if;
  perform public.revoke_cashier_session(token);
  if public.validate_cashier_session(token,sid,did) is not null then raise exception 'revoked session accepted'; end if;
  for i in 1..5 loop perform public.authenticate_cashier(sid,'de000000-0000-0000-0000-000000000001',c,'9999'); end loop;
  if exists(select 1 from public.authenticate_cashier(sid,'de000000-0000-0000-0000-000000000001',c,'1234')) then raise exception 'locked cashier authenticated'; end if;
  if exists(select 1 from information_schema.parameters where specific_schema='public' and specific_name like 'authenticate_cashier_%' and parameter_name='pin_hash') then raise exception 'PIN hash exposed'; end if;
  perform id, display_name, is_active from public.cashiers where id=c;
  begin perform pin_hash from public.cashiers where id=c; raise exception 'PIN hash selectable';
  exception when insufficient_privilege then null; end;
end $$;

-- Rate-limit storage is deliberately server-only, so inspect it as the test
-- administrator rather than granting the client role access to credential data.
reset role;
do $$ begin
  if not exists(
    select 1 from public.cashier_auth_attempts a
    join public.cashiers c on c.id = a.cashier_id and c.shop_id = a.shop_id
    where a.shop_id='aa000000-0000-0000-0000-000000000001'
      and c.login_code='bilal' and a.failed_count=5 and a.blocked_until>now()
  ) then raise exception 'PIN rate limit failed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000001',true);

do $$
declare p jsonb; result jsonb; before_counts bigint[]; after_counts bigint[];
begin
  p := jsonb_build_object(
    'version',1,'operation','sync_sale_transaction','audit_id','ad000000-0000-0000-0000-000000000001',
    'sale',jsonb_build_object('id','5a000000-0000-0000-0000-000000000001','shopId','aa000000-0000-0000-0000-000000000001','cashierId','11000000-0000-0000-0000-000000000001','customerId','ce000000-0000-0000-0000-000000000001','deviceId','dd000000-0000-0000-0000-000000000001','invoiceNumber',null,'subtotal',43000,'discountTotal',0,'taxTotal',0,'grandTotal',43000,'paymentStatus','paid','saleStatus','completed','createdAt',now()),
    'sale_items',jsonb_build_array(
      jsonb_build_object('id','51000000-0000-0000-0000-000000000001','productId','cc000000-0000-0000-0000-000000000001','productNameSnapshot','Coke','barcodeSnapshot',null,'quantity',1000,'costPriceSnapshot',15000,'salePriceSnapshot',18000,'discountAmount',0,'lineTotal',18000,'createdAt',now()),
      jsonb_build_object('id','51000000-0000-0000-0000-000000000002','productId','cc000000-0000-0000-0000-000000000002','productNameSnapshot','Milk','barcodeSnapshot',null,'quantity',1000,'costPriceSnapshot',20000,'salePriceSnapshot',25000,'discountAmount',0,'lineTotal',25000,'createdAt',now())),
    'payments',jsonb_build_array(
      jsonb_build_object('id','52000000-0000-0000-0000-000000000001','paymentMethod','cash','amount',30000,'reference',null,'createdAt',now()),
      jsonb_build_object('id','52000000-0000-0000-0000-000000000002','paymentMethod','credit','amount',13000,'reference',null,'createdAt',now())),
    'inventory_movements',jsonb_build_array(
      jsonb_build_object('id','53000000-0000-0000-0000-000000000001','productId','cc000000-0000-0000-0000-000000000001','type','sale','quantity',-1000,'createdAt',now()),
      jsonb_build_object('id','53000000-0000-0000-0000-000000000002','productId','cc000000-0000-0000-0000-000000000002','type','sale','quantity',-1000,'createdAt',now())),
    'customer_ledger_entries',jsonb_build_array(jsonb_build_object('id','54000000-0000-0000-0000-000000000001','customerId','ce000000-0000-0000-0000-000000000001','amount',13000,'createdAt',now())));
  result := public.sync_sale_transaction(p,null);
  if result->>'status' <> 'inserted' then raise exception 'initial sale sync failed'; end if;
  before_counts := array[(select count(*) from public.sales),(select count(*) from public.sale_items),(select count(*) from public.sale_payments),(select count(*) from public.inventory_movements),(select count(*) from public.customer_ledger_entries),(select count(*) from public.audit_logs)];
  result := public.sync_sale_transaction(p,null);
  if result->>'status' <> 'already_synced' then raise exception 'idempotent replay failed'; end if;
  after_counts := array[(select count(*) from public.sales),(select count(*) from public.sale_items),(select count(*) from public.sale_payments),(select count(*) from public.inventory_movements),(select count(*) from public.customer_ledger_entries),(select count(*) from public.audit_logs)];
  if before_counts <> after_counts then raise exception 'replay duplicated aggregate'; end if;
  begin perform public.sync_sale_transaction(jsonb_set(p,'{sale,grandTotal}','1'::jsonb),null); raise exception 'conflicting replay accepted';
  exception when others then if sqlerrm = 'conflicting replay accepted' then raise; end if; end;
  begin perform public.sync_sale_transaction(jsonb_set(p,'{sale_items,0,lineTotal}','999999'::jsonb),null); raise exception 'forged line total accepted';
  exception when others then if sqlerrm = 'forged line total accepted' then raise; end if; end;
  begin perform public.sync_sale_transaction(jsonb_set(p,'{inventory_movements,0,quantity}','-2000'::jsonb),null); raise exception 'mismatched stock accepted';
  exception when others then if sqlerrm = 'mismatched stock accepted' then raise; end if; end;
end $$;

do $$ declare bad jsonb; begin
  bad := jsonb_build_object('version',1,'operation','sync_sale_transaction','audit_id',gen_random_uuid(),
    'sale',jsonb_build_object('id','5a000000-0000-0000-0000-000000000002','shopId','aa000000-0000-0000-0000-000000000001','cashierId','11000000-0000-0000-0000-000000000001','customerId',null,'deviceId','dd000000-0000-0000-0000-000000000001','subtotal',1,'discountTotal',0,'taxTotal',0,'grandTotal',1,'paymentStatus','paid','saleStatus','completed','createdAt',now()),
    'sale_items',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'productId','cc000000-0000-0000-0000-000000000001','productNameSnapshot','Bad','quantity',-1,'costPriceSnapshot',1,'salePriceSnapshot',1,'discountAmount',0,'lineTotal',1,'createdAt',now())),
    'payments',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'paymentMethod','cash','amount',1,'createdAt',now())),
    'inventory_movements','[]'::jsonb,'customer_ledger_entries','[]'::jsonb);
  begin perform public.sync_sale_transaction(bad,null); exception when others then null; end;
  if exists(select 1 from public.sales where id='5a000000-0000-0000-0000-000000000002') then raise exception 'invalid aggregate did not roll back'; end if;
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform count(*) from public.shops; raise exception 'anonymous read succeeded';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
