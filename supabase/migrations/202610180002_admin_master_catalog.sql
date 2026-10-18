-- Platform admins manage the global product catalog (public.master_products).
--
-- Clients keep select-only access to master_products. The admin panel writes
-- through two security-definer functions that authorise with
-- dukaan_private.require_platform_admin() (listed admin with an MFA, AAL2
-- session; migration 202610160001) and record every change in
-- dukaan_private.platform_audit_log:
--
--   admin_upsert_master_product   creates (p_id null) or edits a row
--   admin_set_master_product_image points a row at its catalog photo
--
-- The photo itself is uploaded by the admin straight to Storage at
-- catalog/<sha256>.jpg (policy product_images_admin_insert, migration
-- 202610180001). The row may only point at a catalog key that exists, so a
-- device never syncs a key that cannot be downloaded. Passing null clears
-- the photo; files are never deleted (keys are content hashes and may be
-- shared).
--
-- Global categories (shop_id null) are the only categories a catalog row may
-- use. Rows are never deleted: is_active = false hides a row from the shop
-- catalog while existing shop products keep their reference.
begin;

create function public.admin_upsert_master_product(
  p_id uuid,
  p_name text,
  p_brand text,
  p_barcode text,
  p_category_id uuid,
  p_default_unit text,
  p_pack_label text,
  p_is_active boolean)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id uuid := p_id;
  v_name text := trim(coalesce(p_name, ''));
  v_barcode text := trim(coalesce(p_barcode, ''));
  v_unit text := lower(trim(coalesce(p_default_unit, '')));
  v_pack text := nullif(trim(coalesce(p_pack_label, '')), '');
  v_old public.master_products;
begin
  perform dukaan_private.require_platform_admin();
  if length(v_name) = 0 or length(v_name) > 200 then
    raise exception 'name is required (at most 200 characters)' using errcode = '22023';
  end if;
  if length(v_barcode) = 0 or length(v_barcode) > 64 then
    raise exception 'barcode is required (at most 64 characters)' using errcode = '22023';
  end if;
  if v_unit not in ('piece','pack','kg','gram','liter','bottle','carton','dozen','unit','bag') then
    raise exception 'unsupported unit' using errcode = '22023';
  end if;
  if p_category_id is not null and not exists(
       select 1 from public.categories c where c.id = p_category_id and c.shop_id is null) then
    raise exception 'category must be a global category' using errcode = '22023';
  end if;
  if exists(select 1 from public.master_products m
             where m.barcode = v_barcode and m.id is distinct from p_id) then
    raise exception 'DPL07: another catalog product already uses this barcode' using errcode = '23505';
  end if;

  if p_id is null then
    v_id := gen_random_uuid();
    insert into public.master_products(id, barcode, name, brand, category_id, default_unit,
                                       pack_label, is_active, created_at, updated_at)
    values (v_id, v_barcode, v_name, trim(coalesce(p_brand, '')), p_category_id, v_unit,
            v_pack, coalesce(p_is_active, true), now(), now());
    perform dukaan_private.audit('platform_admin', 'catalog.product_created', null, null,
      jsonb_build_object('product_id', v_id, 'name', v_name, 'barcode', v_barcode));
  else
    select * into v_old from public.master_products m where m.id = p_id for update;
    if not found then raise exception 'catalog product not found' using errcode = 'P0002'; end if;
    update public.master_products m
       set barcode = v_barcode, name = v_name, brand = trim(coalesce(p_brand, '')),
           category_id = p_category_id, default_unit = v_unit, pack_label = v_pack,
           is_active = coalesce(p_is_active, m.is_active), updated_at = now()
     where m.id = p_id;
    perform dukaan_private.audit('platform_admin', 'catalog.product_updated', null, null,
      jsonb_build_object('product_id', p_id, 'name', v_name, 'barcode', v_barcode,
                         'from_name', v_old.name, 'from_barcode', v_old.barcode,
                         'is_active', coalesce(p_is_active, v_old.is_active)));
  end if;
  return v_id;
end $$;

create function public.admin_set_master_product_image(p_id uuid, p_path text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare v_old text;
begin
  perform dukaan_private.require_platform_admin();
  if p_path is not null then
    if p_path !~ '^catalog/[0-9a-f]{64}\.jpg$' then
      raise exception 'image path must be a catalog photo key' using errcode = '22023';
    end if;
    if not exists(select 1 from storage.objects o
                   where o.bucket_id = 'product-images' and o.name = p_path) then
      raise exception 'DPL08: upload the photo before attaching it' using errcode = 'P0002';
    end if;
  end if;
  select m.default_image_path into v_old from public.master_products m where m.id = p_id for update;
  if not found then raise exception 'catalog product not found' using errcode = 'P0002'; end if;
  update public.master_products m set default_image_path = p_path, updated_at = now()
   where m.id = p_id;
  perform dukaan_private.audit('platform_admin',
    case when p_path is null then 'catalog.image_cleared' else 'catalog.image_set' end,
    null, null, jsonb_build_object('product_id', p_id, 'path', p_path, 'from', v_old));
end $$;

revoke all on function public.admin_upsert_master_product(uuid,text,text,text,uuid,text,text,boolean)
  from public, anon, authenticated;
grant execute on function public.admin_upsert_master_product(uuid,text,text,text,uuid,text,text,boolean)
  to authenticated;
revoke all on function public.admin_set_master_product_image(uuid,text) from public, anon, authenticated;
grant execute on function public.admin_set_master_product_image(uuid,text) to authenticated;

commit;
