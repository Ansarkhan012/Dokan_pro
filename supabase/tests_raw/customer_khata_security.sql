-- Customer owner management, immutable ledger, payment idempotency and isolation.
begin;
insert into auth.users(id,email) values
 ('51000000-0000-0000-0000-000000000001','khata-owner-a@example.test'),
 ('52000000-0000-0000-0000-000000000002','khata-owner-b@example.test');
insert into public.shops(id,name) values
 ('5a000000-0000-0000-0000-000000000001','Khata Shop A'),
 ('5b000000-0000-0000-0000-000000000002','Khata Shop B');
insert into public.shop_users(shop_id,user_id,role) values
 ('5a000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001','owner'),
 ('5b000000-0000-0000-0000-000000000002','52000000-0000-0000-0000-000000000002','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier) values
 ('5d000000-0000-0000-0000-000000000001','5a000000-0000-0000-0000-000000000001','Counter','windowsDesktop','5e000000-0000-0000-0000-000000000001');
insert into public.customers(id,shop_id,name,credit_limit,created_at,updated_at) values
 ('5c000000-0000-0000-0000-000000000001','5a000000-0000-0000-0000-000000000001','Ahmed Khan',500000,now(),now());
insert into public.customer_ledger_entries(id,shop_id,customer_id,type,amount,created_by,created_at) values
 ('5c000000-0000-0000-0000-000000000002','5a000000-0000-0000-0000-000000000001','5c000000-0000-0000-0000-000000000001','openingBalance',20000,'51000000-0000-0000-0000-000000000001',now());

set local role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true);
do $$
declare customer_id uuid; payload jsonb; result jsonb;
begin
  customer_id := public.save_customer('5a000000-0000-0000-0000-000000000001','5c000000-0000-0000-0000-000000000001',
    'Ahmed Khan','03001234567','Street 1','Trusted customer',500000,true);
  if customer_id is null then raise exception 'customer create failed'; end if;
  begin
    perform public.save_customer('5b000000-0000-0000-0000-000000000002',null,'Cross shop',null,null,null,null,true);
    raise exception 'cross-shop customer create succeeded';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.customer_ledger_entries(id,shop_id,customer_id,type,amount,created_by,created_at)
      values(gen_random_uuid(),'5a000000-0000-0000-0000-000000000001',customer_id,'paymentReceived',100,
        '51000000-0000-0000-0000-000000000001',now());
    raise exception 'direct financial insert succeeded';
  exception when insufficient_privilege then null; end;

  payload := jsonb_build_object('version',1,'operation','sync_customer_payment',
    'entry',jsonb_build_object('id','5f000000-0000-0000-0000-000000000001','shop_id','5a000000-0000-0000-0000-000000000001',
      'customer_id',customer_id,'type','paymentReceived','amount',10000,'payment_method','cash',
      'created_by','51000000-0000-0000-0000-000000000001','created_at','2026-09-13T12:00:00Z'),
    'audit',jsonb_build_object('id','5f000000-0000-0000-0000-000000000002','shop_id','5a000000-0000-0000-0000-000000000001',
      'user_id','51000000-0000-0000-0000-000000000001','action','customer.payment_received',
      'entity_type','customer_ledger_entry','entity_id','5f000000-0000-0000-0000-000000000001',
      'new_value',jsonb_build_object('amount',10000,'method','cash'),'device_id','5d000000-0000-0000-0000-000000000001',
      'created_at','2026-09-13T12:00:00Z'));
  result := public.sync_customer_payment(payload,null);
  if result->>'status' <> 'inserted' then raise exception 'payment insert failed: %',result; end if;
  result := public.sync_customer_payment(payload,null);
  if result->>'status' <> 'already_synced' then raise exception 'payment replay not idempotent: %',result; end if;
  if (select count(*) from public.customer_ledger_entries where id='5f000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'payment replay duplicated ledger'; end if;
  if (select count(*) from public.audit_logs where entity_id='5f000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'payment replay duplicated audit'; end if;
  begin
    perform public.sync_customer_payment(
      jsonb_set(jsonb_set(payload,'{entry,id}','"5f000000-0000-0000-0000-000000000003"'),'{entry,amount}','10001'),null);
    raise exception 'customer overpayment accepted';
  exception when check_violation then null; end;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  begin perform count(*) from public.customers; raise exception 'anonymous customer read succeeded';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_customer('5a000000-0000-0000-0000-000000000001',null,
      'Cashier escalation',null,null,null,null,true);
    raise exception 'non-owner customer management succeeded';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
