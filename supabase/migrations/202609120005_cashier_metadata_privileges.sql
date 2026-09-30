begin;
revoke select on public.cashiers from anon, authenticated;
grant select(id, shop_id, display_name, login_code, credential_version, is_active, created_at, updated_at)
  on public.cashiers to authenticated;
commit;
