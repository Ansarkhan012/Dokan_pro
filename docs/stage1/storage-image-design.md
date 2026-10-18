# Product images across devices: Supabase Storage design

Status: **DESIGN ONLY — not approved, nothing created.** No bucket, policy,
migration, Edge Function or cloud record exists for this. Implementing it
needs separate approval because every part below except §6–§8 is a cloud change.

Fixes Stage 1 findings **IMG-1** (a photo picked on one device never reaches
another) and **IMG-2** (a synced Storage key is treated as a local file path
and always shows the placeholder).

## 1. Current state (verified in code)

- Photos are processed on device (`prepareProductThumbnail`: EXIF orientation,
  flatten alpha, ≤512 px, JPEG q80, ~20–60 KB) and written to
  `<app support>/product_images/<shop_product_id>.jpg`.
- `shop_products.image_path` is never written by the app. Cross-device display
  is impossible today; same-device display and restart persistence work
  (covered by `test/product_image_test.dart`, `test/stage1_regressions_test.dart`).
- Cashier tablets do **not** hold an owner Supabase Auth session. They call
  `device_pull` etc. with the `x-dukaan-device` credential header. Storage RLS
  keyed on `auth.uid()` therefore cannot authorise cashier downloads by itself.

## 2. Bucket choice: private `product-images`

| Option | Verdict |
| --- | --- |
| Public bucket | Rejected. URLs are guessable from `shop_id/product_id`, enumerate a shop's catalogue, and can never be revoked for a removed device. |
| **Private bucket + server-issued signed URLs** | **Chosen.** Works for owner sessions and device-credential cashiers; URLs are short-lived. |

Bucket settings: `public = false`, `file_size_limit = 262144` (256 KB, ~4× the
largest expected thumbnail), `allowed_mime_types = {image/jpeg}`.

## 3. Object layout and the synced reference

- Object key: `<shop_id>/<shop_product_id>/<sha256-prefix-16>.jpg`.
  The content hash in the name makes every change a new key, so caches never
  serve a stale image and no CDN invalidation is needed.
- `shop_products.image_path` stores that key (never a URL — signed URLs
  expire). It already exists, is already pulled (`reference_pull_service`) and
  already ordered by `server_seq`, so no new sync entity is needed.
- Master catalogue `default_image_path` follows the same rule under a
  `catalog/` prefix, readable by any authenticated owner or valid device.

## 4. Tenant isolation and RLS (all server-side)

- `storage.objects` **INSERT/UPDATE/DELETE**: allowed only when
  `bucket_id = 'product-images'` and the first path segment is a shop for which
  `public.is_active_owner(shop_id)` is true. Cashiers never write images.
- `storage.objects` **SELECT**: owners of that shop only (same predicate).
- **Cashier devices**: a new Edge Function `product-image-urls` validates the
  device credential exactly like the existing device RPCs (active device,
  active shop, not revoked), takes up to 100 keys, rejects any key whose first
  segment is not the device's shop, and returns signed URLs valid for 10 min.
  The service-role key stays inside the function, never on a device.
- Setting `image_path`: a new owner RPC `set_shop_product_image(product_id,
  key)` checks ownership, that the key's prefix is `<shop_id>/<product_id>/`
  and that the object exists, then bumps `server_seq`. Direct column grants on
  `image_path` should be revoked if still present.
- pgTAP/raw SQL tests: owner A cannot read/write shop B's prefix; a cashier
  token cannot upload; a revoked device gets no URLs; a forged cross-shop key
  is refused.

## 5. Upload flow (owner device)

1. Existing local processing and local save (unchanged; the image shows at once).
2. Enqueue an `upload_product_image` operation in the existing sync queue
   (payload: product id, local file name, sha256). Never blocks product create.
3. Worker uploads with `upsert: false` to the hashed key (a retry of the same
   bytes hits the same key → "already exists" is treated as success, so
   delivery is idempotent), then calls `set_shop_product_image`.
4. Failures use the existing classification (retry/backoff, needsAttention);
   the local image keeps showing meanwhile.

## 6. Download and local cache (client)

- Keep `ProductImageStore` as the single cache, adding a sidecar index
  `<id>.key` holding the Storage key the file came from.
- Resolution order (implements the unused `ProductImageCache` /
  `ProductImageSource` interfaces): local file whose key matches
  `image_path` → `CachedProductImage`; else `RemoteProductImage(key)`;
  else `MissingProductImage` → placeholder.
- After each successful reference pull, a background prefetch collects
  products whose cached key ≠ `image_path`, requests signed URLs in batches,
  downloads with a 15 s timeout, verifies JPEG decode and the sha256 prefix,
  and saves atomically (existing temp + rename). Never during checkout.
- Thumbnails never fetch the network themselves: the POS grid only reads the
  local cache, so billing speed is unaffected and offline behaviour is identical
  to online.

## 7. Offline behaviour

- Everything already cached shows offline and after restart (app-support
  storage, indexed at startup).
- Not yet downloaded → placeholder; the prefetch retries on the next pull.
- Images are never required for search, barcode scan, checkout or receipts.

## 8. Compression and limits

- Unchanged pipeline: ≤512 px longest side, JPEG q80, alpha flattened, EXIF
  applied, 25 MB / 40 MP input guards. Server limit 256 KB rejects anything
  that bypassed it.
- Estimated footprint: 2,000 products × ~40 KB ≈ 80 MB per shop.

## 9. Cleanup

- Replacing an image: the RPC records the old key; a scheduled Edge Function
  deletes unreferenced objects older than 7 days (grace period for devices
  that have not pulled yet).
- Product deactivation keeps the image (reactivation is common).
- Client: when the pulled `image_path` changes or becomes null, the old local
  file is replaced or removed; orphan files (no active product) are pruned on
  startup, at most once a day.

## 10. Migration of existing images

Images already on the owner's device can be backfilled by enqueueing one
upload per indexed local file after the feature ships. Images that exist only
on another tablet must be re-uploaded from that tablet (or re-picked).

## 11. Approval checklist (cloud changes)

- [ ] Bucket `product-images` (private, 256 KB, image/jpeg)
- [ ] `storage.objects` policies (owner prefix)
- [ ] RPC `set_shop_product_image` + revoke direct `image_path` grant
- [ ] Edge Function `product-image-urls` (device credential → signed URLs)
- [ ] Cleanup Edge Function + schedule
- [ ] pgTAP / raw SQL / HTTP tests for all of the above, run locally first
