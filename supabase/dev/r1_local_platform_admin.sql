-- LOCAL DISPOSABLE STACKS ONLY. Never apply to a hosted Supabase project.
--
-- Since migration 202610140001 only platform administrators create shops.
-- The R1 HTTP harness has no service-role key, so on its scratch database any
-- account signed up with an @r1-admin.test address becomes a platform admin.
-- Applied by tool/r1_integration/local_http_stack.sh and the CI R1 job after
-- migrations and seed; not a migration, never deployed.
create or replace function dukaan_private.r1_local_promote_admin() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email like '%@r1-admin.test' then
    insert into dukaan_private.platform_admins(user_id, note)
    values (new.id, 'R1 local harness') on conflict do nothing;
  end if;
  return new;
end $$;
revoke all on function dukaan_private.r1_local_promote_admin() from public, anon, authenticated;
drop trigger if exists r1_local_promote_admin on auth.users;
create trigger r1_local_promote_admin after insert on auth.users
  for each row execute function dukaan_private.r1_local_promote_admin();
