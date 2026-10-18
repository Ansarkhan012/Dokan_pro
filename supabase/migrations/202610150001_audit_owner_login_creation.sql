-- Audits owner logins created by the admin-create-owner Edge Function.
--
-- 202610140001 audited every shop, owner, licence and device decision but not
-- the creation of the owner's auth account, which happens in the Edge Function
-- with the service-role key. The function now calls this RPC with the
-- administrator's own JWT right after creating the account, so the audit row
-- carries the real admin as actor (auth.uid()), never an ID from the request.
--
-- Only accounts created in the last 10 minutes that are not platform admins
-- can be recorded, so the RPC cannot be used to write misleading entries about
-- older accounts.
begin;

create function public.admin_record_owner_login_created(p_user_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_email text;
begin
  perform dukaan_private.require_platform_admin();
  select u.email into v_email from auth.users u
   where u.id = p_user_id and u.created_at > now() - interval '10 minutes';
  if v_email is null then
    raise exception 'recently created account required' using errcode = 'P0002';
  end if;
  if exists(select 1 from dukaan_private.platform_admins a where a.user_id = p_user_id) then
    raise exception 'platform administrator accounts are not owner logins' using errcode = '42501';
  end if;
  perform dukaan_private.audit('platform_admin', 'owner.login_created', null, null,
    jsonb_build_object('owner_user_id', p_user_id, 'owner_email', lower(v_email)));
end $$;
revoke all on function public.admin_record_owner_login_created(uuid) from public, anon, authenticated;
grant execute on function public.admin_record_owner_login_created(uuid) to authenticated;

commit;
