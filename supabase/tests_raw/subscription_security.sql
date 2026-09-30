begin;
insert into auth.users(id,email) values
 ('c1000000-0000-0000-0000-000000000001','sub-owner-a@example.test'),
 ('c2000000-0000-0000-0000-000000000002','sub-owner-b@example.test');
insert into public.shops(id,name) values
 ('ca000000-0000-0000-0000-000000000001','Sub A'),
 ('cb000000-0000-0000-0000-000000000002','Sub B');
insert into public.shop_users(shop_id,user_id,role) values
 ('ca000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','owner'),
 ('cb000000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000002','owner');
insert into public.devices(id,shop_id,device_name,device_type,device_identifier,is_active) values
 ('cd000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','A','windowsDesktop','ce000000-0000-0000-0000-000000000001',true),
 ('cd000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000001','Revoked','windowsDesktop','ce000000-0000-0000-0000-000000000002',false);
set local role authenticated;
select set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000001',true);
do $$ begin
  perform public.entitlement_claims('ca000000-0000-0000-0000-000000000001','cd000000-0000-0000-0000-000000000001');
  begin perform public.entitlement_claims('cb000000-0000-0000-0000-000000000002','cd000000-0000-0000-0000-000000000001'); raise exception 'cross-shop claims allowed'; exception when insufficient_privilege then null; end;
  begin perform public.entitlement_claims('ca000000-0000-0000-0000-000000000001','cd000000-0000-0000-0000-000000000002'); raise exception 'revoked device claims allowed'; exception when insufficient_privilege then null; end;
  begin update public.shop_subscriptions set period_end=now()+interval '10 years'; raise exception 'direct subscription mutation allowed'; exception when insufficient_privilege then null; end;
end $$;
rollback;
