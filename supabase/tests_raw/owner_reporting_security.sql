begin;
insert into auth.users(id,email) values
 ('91000000-0000-0000-0000-000000000001','report-a@test'),
 ('92000000-0000-0000-0000-000000000002','report-b@test');
insert into public.shops(id,name) values
 ('9a000000-0000-0000-0000-000000000001','Report A'),
 ('9b000000-0000-0000-0000-000000000002','Report B');
insert into public.shop_users(shop_id,user_id,role) values
 ('9a000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','owner'),
 ('9b000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','owner');

set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
do $$
declare r jsonb;
begin
  r := public.owner_report_summary('9a000000-0000-0000-0000-000000000001','2026-01-01','2027-01-01');
  if (r->>'sales')::bigint <> 0 then raise exception 'unexpected own-shop total'; end if;
  begin
    perform public.owner_report_summary('9b000000-0000-0000-0000-000000000002','2026-01-01','2027-01-01');
    raise exception 'cross-shop report succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
  begin
    perform public.owner_report_summary('9a000000-0000-0000-0000-000000000001','2026-01-01','2027-01-01');
    raise exception 'anonymous report succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
