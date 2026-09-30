-- Run after migrations against an isolated local Supabase database.
begin;
insert into auth.users(id, email) values
  ('10000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('20000000-0000-0000-0000-000000000002', 'owner-b@example.test');
insert into public.shops(id, name) values
  ('a0000000-0000-0000-0000-000000000001', 'Shop A'),
  ('b0000000-0000-0000-0000-000000000002', 'Shop B');
insert into public.shop_users(shop_id, user_id, role) values
  ('a0000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'owner'),
  ('b0000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'owner');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
do $$ begin
  if (select count(*) from public.shops) <> 1 then raise exception 'Owner A shop isolation failed'; end if;
  insert into public.customers(id, shop_id, name, created_at, updated_at)
    values('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Allowed', now(), now());
  begin
    insert into public.customers(id, shop_id, name, created_at, updated_at)
      values('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'Denied', now(), now());
    raise exception 'Owner A cross-shop write unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$ begin
  begin
    perform count(*) from public.shops;
    raise exception 'Anonymous tenant read unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;
rollback;
