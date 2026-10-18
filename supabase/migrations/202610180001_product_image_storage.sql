-- Product images live in Supabase Storage, never in table rows. Rows keep
-- only a short storage key in shop_products.image_path or
-- master_products.default_image_path:
--
--   catalog/<sha256>.jpg            global catalog, written by platform admins
--   shops/<shop_id>/<sha256>.jpg    a shop's own photo, written by its owner
--
-- Keys are content hashes, so a file never changes after upload: devices
-- cache it forever and the same photo is stored once. The bucket is public
-- for reading (product photos are not secret) and only accepts the small
-- JPEGs the app produces on the device (512px, about 30-60 KB).
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 524288, array['image/jpeg'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- The shop a `shops/<shop_id>/<sha256>.jpg` key belongs to; null for any
-- other name, so a malformed key never reaches a uuid cast.
create function public.product_image_shop_id(p_name text) returns uuid
language sql immutable set search_path = '' as $$
  select case
    when p_name ~ '^shops/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{64}\.jpg$'
    then split_part(p_name, '/', 2)::uuid
  end;
$$;
revoke all on function public.product_image_shop_id(text) from public, anon;
grant execute on function public.product_image_shop_id(text) to authenticated;

-- Insert only: content-addressed files are never overwritten, and nothing
-- is deleted from a device (another product of the shop may share a file).
create policy product_images_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'product-images'
    and public.is_active_owner(public.product_image_shop_id(name))
  );

create policy product_images_admin_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'product-images'
    and name ~ '^catalog/[0-9a-f]{64}\.jpg$'
    and public.is_platform_admin()
  );

commit;
