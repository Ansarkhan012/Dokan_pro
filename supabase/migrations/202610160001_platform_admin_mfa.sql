-- Platform administrators must hold a verified MFA session (AAL2).
--
-- Every admin_* function, admin_record_owner_login_created and the
-- admin-create-owner Edge Function authorise through public.is_platform_admin()
-- (directly or via dukaan_private.require_platform_admin()). It now also
-- requires the caller's JWT to carry aal = 'aal2', which Supabase Auth issues
-- only after a verified TOTP challenge. A password-only (aal1) session of a
-- listed admin is refused everywhere. The claim comes from the JWT that
-- PostgREST has already verified, so it cannot be forged by a client; there is
-- no bypass role or code. Service-role connections have no auth.uid() and are
-- not admins either (unchanged).
--
-- public.platform_admin_access() lets the admin panel tell its own user which
-- step is missing (enrol / verify MFA) without granting anything: it reports
-- only on the caller, and every privileged call still checks
-- is_platform_admin().
--
-- Owners and cashiers are untouched: no other function reads the AAL.
begin;

create or replace function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
     and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
     and exists(select 1 from dukaan_private.platform_admins a
                 where a.user_id = auth.uid() and a.is_active);
$$;
revoke all on function public.is_platform_admin() from public, anon, authenticated;
grant execute on function public.is_platform_admin() to authenticated;

-- 'none'         not an active platform admin (owners, cashiers, others)
-- 'mfa_required' listed admin, session below AAL2: enrol or verify TOTP
-- 'granted'      listed admin with an AAL2 session
create function public.platform_admin_access() returns text
language sql stable security definer set search_path = '' as $$
  select case
    when auth.uid() is null
      or not exists(select 1 from dukaan_private.platform_admins a
                     where a.user_id = auth.uid() and a.is_active) then 'none'
    when coalesce(auth.jwt() ->> 'aal', '') = 'aal2' then 'granted'
    else 'mfa_required'
  end;
$$;
revoke all on function public.platform_admin_access() from public, anon, authenticated;
grant execute on function public.platform_admin_access() to authenticated;

commit;
