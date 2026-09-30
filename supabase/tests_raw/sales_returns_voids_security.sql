begin;
insert into auth.users(id,email) values
 ('b1000000-0000-0000-0000-000000000001','returns-owner-a@example.test'),
 ('b2000000-0000-0000-0000-000000000002','returns-owner-b@example.test');
insert into public.shops(id,name) values
 ('ba000000-0000-0000-0000-000000000001','Returns A'),
 ('bb000000-0000-0000-0000-000000000002','Returns B');
insert into public.shop_users(shop_id,user_id,role) values
 ('ba000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','owner'),
 ('bb000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000002','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier) values
 ('bd000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000001','Counter','windowsDesktop','bc000000-0000-0000-0000-000000000001');
insert into public.categories(id,shop_id,name,created_at,updated_at) values
 ('b3000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000001','Staples',now(),now());
insert into public.shop_products(id,shop_id,custom_name,category_id,unit,purchase_price,sale_price,created_at,updated_at) values
 ('be000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000001','Rice','b3000000-0000-0000-0000-000000000001','kg',10000,12000,now(),now());
insert into public.customers(id,shop_id,name,created_at,updated_at) values
 ('bf000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000001','Ahmed',now(),now());
insert into public.sales(id,shop_id,cashier_id,customer_id,device_id,subtotal,discount_total,tax_total,grand_total,payment_status,sale_status,created_at) values
 ('c1000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','bf000000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000001',12000,0,0,12000,'paid','completed',now()),
 ('c1000000-0000-0000-0000-000000000002','ba000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',null,'bd000000-0000-0000-0000-000000000001',12000,0,0,12000,'paid','completed',now());
insert into public.sale_items(id,shop_id,sale_id,product_id,product_name_snapshot,quantity,cost_price_snapshot,sale_price_snapshot,discount_amount,line_total,created_at) values
 ('c2000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','be000000-0000-0000-0000-000000000001','Rice',1000,10000,12000,0,12000,now()),
 ('c2000000-0000-0000-0000-000000000002','ba000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','be000000-0000-0000-0000-000000000001','Rice',1000,10000,12000,0,12000,now());
insert into public.sale_payments(id,shop_id,sale_id,payment_method,amount,created_at) values
 ('c3000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','credit',12000,now()),
 ('c3000000-0000-0000-0000-000000000002','ba000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','cash',12000,now());

set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
do $$declare p jsonb;r jsonb;begin
 p:=jsonb_build_object('version',1,'operation','sync_sale_return','return',jsonb_build_object('id','c4000000-0000-0000-0000-000000000001','shop_id','ba000000-0000-0000-0000-000000000001','original_sale_id','c1000000-0000-0000-0000-000000000001','device_id','bd000000-0000-0000-0000-000000000001','refund_method','credit','refund_amount',6000,'reason','Half returned','created_by','b1000000-0000-0000-0000-000000000001','created_at',now()),'items',jsonb_build_array(jsonb_build_object('id','c5000000-0000-0000-0000-000000000001','original_sale_item_id','c2000000-0000-0000-0000-000000000001','product_id','be000000-0000-0000-0000-000000000001','product_name_snapshot','Rice','quantity',500,'unit_price_snapshot',12000,'refund_amount',6000)),'inventory_movements',jsonb_build_array(jsonb_build_object('id','c6000000-0000-0000-0000-000000000001','product_id','be000000-0000-0000-0000-000000000001','type','returnIn','quantity',500)),'ledger_id','c7000000-0000-0000-0000-000000000001','audit_id','c8000000-0000-0000-0000-000000000001');
 r:=public.sync_sale_return(p,null);if r->>'status'<>'inserted'then raise exception 'return insert failed';end if;
 r:=public.sync_sale_return(p,null);if r->>'status'<>'already_synced'then raise exception 'return replay failed';end if;
 if(select count(*) from public.sale_return_items where return_id='c4000000-0000-0000-0000-000000000001')<>1 then raise exception 'return duplicated';end if;
 begin perform public.sync_sale_return(jsonb_set(p,'{return,refund_amount}','5000'),null);raise exception 'conflicting return replay succeeded';exception when others then if sqlerrm='conflicting return replay succeeded'then raise;end if;end;
 begin perform public.sync_sale_return(jsonb_set(jsonb_set(jsonb_set(p,'{return,id}','"c4000000-0000-0000-0000-000000000002"'),'{items,0,id}','"c5000000-0000-0000-0000-000000000002"'),'{items,0,quantity}','501'),null);raise exception 'over-return succeeded';exception when others then if sqlerrm='over-return succeeded'then raise;end if;end;
end$$;

do $$declare p jsonb;r jsonb;begin
 p:=jsonb_build_object('version',2,'operation','sync_sale_void','void',jsonb_build_object('id','c9000000-0000-0000-0000-000000000001','shop_id','ba000000-0000-0000-0000-000000000001','original_sale_id','c1000000-0000-0000-0000-000000000002','device_id','bd000000-0000-0000-0000-000000000001','amount',12000,'reason','Wrong bill','payment_breakdown',jsonb_build_object('cash',12000),'created_by','b1000000-0000-0000-0000-000000000001','created_at',now()),'movement_ids',jsonb_build_object('c2000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000001'),'refund_ledger_id',null,'audit_id','ca000000-0000-0000-0000-000000000001');
 -- R1.3: a v1 void (no compensation ids) is refused with DPV01 before any write.
 begin perform public.sync_sale_void(jsonb_set(p,'{version}','1')-'movement_ids'-'refund_ledger_id',null);raise exception 'v1 void accepted';exception when sqlstate 'DPV01' then null;end;
 if exists(select 1 from public.sale_voids where original_sale_id='c1000000-0000-0000-0000-000000000002') then raise exception 'v1 void wrote a row';end if;
 r:=public.sync_sale_void(p,null);if r->>'status'<>'inserted'then raise exception 'void insert failed';end if;
 r:=public.sync_sale_void(p,null);if r->>'status'<>'already_synced'then raise exception 'void replay failed';end if;
 if(select count(*) from public.sale_voids where original_sale_id='c1000000-0000-0000-0000-000000000002')<>1 then raise exception 'void duplicated';end if;
 if(select id from public.inventory_movements where reference_id='c9000000-0000-0000-0000-000000000001')<>'cb000000-0000-0000-0000-000000000001' then raise exception 'void compensation id not the client id';end if;
end$$;

do $$begin
 begin insert into public.sale_returns(id,shop_id,original_sale_id,device_id,refund_method,refund_amount,reason,created_by,created_at,aggregate_hash) values(gen_random_uuid(),'ba000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000001','cash',1,'direct','b1000000-0000-0000-0000-000000000001',now(),'x');raise exception 'direct return insert succeeded';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','',true);set local role anon;
do $$begin begin perform public.sync_sale_return('{}',null);raise exception 'anonymous return succeeded';exception when insufficient_privilege then null;end;end$$;
rollback;
