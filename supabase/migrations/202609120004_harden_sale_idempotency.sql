begin;

alter function public.sync_sale_transaction(jsonb) rename to sync_sale_transaction_owner_legacy;
revoke all on function public.sync_sale_transaction_owner_legacy(jsonb) from public, anon, authenticated;

create or replace function public.sync_sale_transaction(p_payload jsonb, p_cashier_token text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare
  v_sale jsonb := p_payload -> 'sale';
  v_sale_id uuid := (v_sale ->> 'id')::uuid;
  v_shop_id uuid := (v_sale ->> 'shopId')::uuid;
  v_cashier_id uuid := (v_sale ->> 'cashierId')::uuid;
  v_device_id uuid := (v_sale ->> 'deviceId')::uuid;
  v_hash bytea := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  v_existing_hash bytea;
  v_session_cashier uuid;
  v_owner_id uuid;
  v_original_sub text := current_setting('request.jwt.claim.sub', true);
  v_result jsonb;
begin
  -- Serialize retries for the same immutable aggregate identity.
  perform pg_advisory_xact_lock(hashtextextended(v_sale_id::text, 0));

  if public.is_active_owner(v_shop_id) then
    null;
  elsif p_cashier_token is not null then
    v_session_cashier := public.validate_cashier_session(p_cashier_token, v_shop_id, v_device_id);
    if v_session_cashier is null or v_session_cashier <> v_cashier_id then
      raise exception 'invalid cashier session' using errcode = '42501';
    end if;
  else
    raise exception 'owner or cashier session required' using errcode = '42501';
  end if;

  select aggregate_hash into v_existing_hash from public.sales where id = v_sale_id and shop_id = v_shop_id;
  if found then
    if v_existing_hash is null then raise exception 'existing sale predates aggregate fingerprint'; end if;
    if v_existing_hash <> v_hash then raise exception 'conflicting replay for immutable sale'; end if;
    return jsonb_build_object('sale_id', v_sale_id, 'status', 'already_synced');
  end if;

  if v_session_cashier is not null then
    select su.user_id into v_owner_id from public.shop_users su
      where su.shop_id = v_shop_id and su.role = 'owner' and su.is_active order by su.created_at limit 1;
    if v_owner_id is null then raise exception 'shop has no active owner'; end if;
    perform set_config('request.jwt.claim.sub', v_owner_id::text, true);
  end if;

  v_result := public.sync_sale_transaction_owner_legacy(p_payload);
  update public.sales set aggregate_hash = v_hash where id = v_sale_id and shop_id = v_shop_id;
  if v_session_cashier is not null then
    perform set_config('request.jwt.claim.sub', coalesce(v_original_sub, ''), true);
  end if;
  return v_result;
exception when others then
  if v_session_cashier is not null then
    perform set_config('request.jwt.claim.sub', coalesce(v_original_sub, ''), true);
  end if;
  raise;
end; $$;

revoke all on function public.sync_sale_transaction(jsonb,text) from public;
grant execute on function public.sync_sale_transaction(jsonb,text) to anon, authenticated;

commit;
