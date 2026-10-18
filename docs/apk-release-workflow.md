# Private APK releases and in-app updates

Dokan Pro is distributed as signed APKs, not through Google Play. Installed
apps find new releases through a **signed manifest** and update **in place**
through Android's own installer, so app data (Drift database, unsynced sales,
device registration, Udhaar, products, images) is kept.

Code: `lib/features/app_update/`, native installer in
`android/app/src/main/kotlin/com/dukaanpro/dukaan_pro/MainActivity.kt`,
tests in `test/app_update_test.dart`, release tool `tool/release/update_manifest.dart`.

## How it works

1. A few seconds after start and on return to the foreground (at most every
   6 h; Settings → *Check for updates* any time) the app fetches
   `APP_UPDATE_MANIFEST_URL`. Offline or errors: silent, POS unaffected.
2. The manifest must carry a valid **RS256 signature by the update-manifest
   key** (public half compiled into the app). The APK URL must be HTTPS on an
   allowed host; package, versionCode, SHA-256, size and dates are validated.
3. Newer `versionCode` → dialog (English/Urdu). It waits while a cart has
   items. "Later" hides that version; a newer one prompts again.
   Required releases (`forceUpdate` or below `minSupportedVersionCode`) have
   no "Later" but always "Continue for now": a manifest never locks billing.
4. "Update now": Android "Install unknown apps" permission (explained, opens
   the setting) → download to `<cache>/app_update/dokan_pro_<code>.apk` with
   progress/cancel/timeout → size + SHA-256 must match the signed manifest →
   Android parses the APK: same package, higher versionCode, signer equal to
   or rotated from the installed signer → PackageInstaller session; Android
   shows its own confirmation and replaces the app in place.
5. Nothing is ever uninstalled, silently installed, or downgraded.

## Keys (two different things)

| Key | Purpose | Where |
|---|---|---|
| APK signing key (`dukaan-release.jks`) + lineage | Android accepts the update as the same app | `C:\Users\ansar\.dukaan\signing\` (`docs/release-signing.md`) |
| Update-manifest key (RSA-3072) | The app trusts a manifest | `C:\Users\ansar\.dukaan\signing\dokan-pro-update-manifest-key.json` (public half: `dokan-pro-update-manifest-public.txt`); encrypted backup `F:\DokanPro_Backups\Signing_Keys\dokan-pro-update-manifest-key.20261016T021856Z.960cd71f.enc.json` (scrypt + AES-256-GCM, recovery verified 2026-10-16) |

Back both up together, offline. Losing the manifest key only means shipping
one release with a new public key via manual install; losing the APK
keystore means no in-place updates ever again.

## Build configuration (`--dart-define`, all public values)

Add to `C:\Users\ansar\.dukaan\pilot_defines.json`:

```json
"APP_UPDATE_MANIFEST_URL": "https://uioaaoacxlslffgmjqio.supabase.co/storage/v1/object/public/app-releases/manifest.json",
"APP_UPDATE_ALLOWED_HOSTS": "uioaaoacxlslffgmjqio.supabase.co",
"APP_UPDATE_RSA_MODULUS_B64URL": "<printed by keygen>",
"APP_UPDATE_RSA_EXPONENT_B64URL": "AQAB"
```

Without them the feature is off and the app behaves as before.

## Hosting recommendation

**Supabase Storage, existing project, public bucket `app-releases`.** No new
account or cost; HTTPS on a host the app already trusts; direct 200
responses (the downloader does not follow redirects, so GitHub Releases,
which redirect to another host, would need an allow-list change).

* One object per release, never overwritten: `dokan_pro_<versionCode>.apk`.
* `manifest.json` is the only object that is replaced; upload it with a short
  cache lifetime (`cacheControl: 60`).
* Free plan egress: a 75–120 MB APK × ~6 devices ≈ 0.5–0.7 GB per release,
  inside the monthly allowance at the current size. At 10+ shops, move the
  APK to Cloudflare R2 (no egress fees) and add its host to the allow-list.
* Creating the bucket is a production change: **needs separate approval.**

## Release procedure (every release)

1. **versionCode:** raise `version:` in `pubspec.yaml` (`1.0.1+2`, then
   `1.0.2+3`, ...). Every installed build today is `versionCode 1`; the
   updater refuses equal or lower codes.
2. **Build:** `flutter build apk --release --dart-define-from-file="C:\Users\ansar\.dukaan\pilot_defines.json"`
3. **Sign with lineage** exactly as in `docs/release-signing.md` (v2 debug key
   + v3 release key + `debug-to-release.lineage`). A release-key-only APK
   cannot update a debug-signed tablet; the app refuses it before Android
   does.
4. **Verify** (build-tools 37):
   ```bash
   aapt2 dump badging dukaan-release.apk | grep "package:"
   ```
   expect `name='com.dukaanpro.dukaan_pro'` and the new versionCode;
   ```bash
   java -jar apksigner.jar lineage --in dukaan-release.apk --print-certs
   ```
   expect signer #1 `3c0612…efd7b3` (debug), #2 `8ac9097e…d0441b` (release).
5. **Archive:** copy to `C:\Users\ansar\.dukaan\apk\dokan-pro-<versionName>-<code>.apk`
   (new name, never overwrite) and record `sha256sum` and the size.
6. **Manifest:** write `payload.json` (fields in `update_manifest.dart`; notes
   in English and Urdu; `publishedAt` now, UTC), then
   ```bash
   dart run tool/release/update_manifest.dart sign payload.json C:/Users/ansar/.dukaan/signing/dokan-pro-update-manifest-key.json manifest-<code>.json dokan-pro-<versionName>-<code>.apk uioaaoacxlslffgmjqio.supabase.co
   ```
   It checks size/SHA-256 against the APK and re-reads the manifest with the
   app's own validator.
7. **Upload the APK** as `app-releases/dokan_pro_<code>.apk`, then verify:
   `curl -sI <apkUrl>` → `200` and the exact `content-length`; download it
   again and compare SHA-256.
8. **Publish the manifest** (`manifest-<code>.json` → `app-releases/manifest.json`)
   only after step 7 passed. Rollback = re-upload the previous manifest.
9. **Test** on a test device with the previous version: the dialog appears
   (or Settings → Check for updates), install completes, data is intact.
10. Then let shop devices update.

## First rollout (one-time)

Installed builds (`versionCode 1`) do not contain the updater. The first
updater-enabled release (`versionCode` ≥ 2) must reach each device once by
the existing manual in-place method (`adb install -r` or opening the APK on
the device; **never uninstall**). Every later release can update in-app.

## Two-version in-place upgrade test (before any shop device)

On an **emulator or spare test device**, never the shop tablet:

1. Build A = `1.0.1+2` and B = `1.0.2+3`, both lineage-signed, updater on,
   pointing at a test bucket/manifest.
2. Install A (`adb install`). Sign in, register the device, make sales
   offline, add a customer with Udhaar, a product image; note the sync queue,
   device code, sales count, preferences (language).
3. Publish B's manifest. Bring A to the foreground: dialog shows A → B, size,
   notes; check Urdu RTL too. Try "Later" (no re-prompt), Settings → Check.
4. Update now: permission screen, progress, cancel mid-way, airplane mode
   mid-way (timeout + retry), then complete. Android confirmation → app
   restarts as B.
5. Verify in B: same device code (no new registration), owner still signed
   in, all sales/Udhaar/products/images present, unsynced queue uploads.
6. Negative cases: manifest with wrong signature (ignored), APK with wrong
   SHA-256 (rejected, deleted), APK signed by another key (refused before
   install), manifest listing A's versionCode (no prompt).

Only after this passes on a test device: one supervised update of the
Samsung tablet, with the sync chip showing **Synced** beforehand.

## Testing versionCode 2 → versionCode 3

The updater-enabled build `1.0.1+2` (below) checks
`APP_UPDATE_MANIFEST_URL` a few seconds after start, on every return to the
foreground (at most every 6 h) and from Settings → *Check for updates*. While
`app-releases/manifest.json` does not exist the check fails silently and the
POS is unaffected.

1. On an emulator or spare device (never the shop tablet), install
   `dokan-pro-1.0.1-2-updater-enabled-release.apk` with `adb install -r`
   over the build it runs today. Create test data (offline sales, Udhaar,
   product image) and note the device code and sync queue.
2. Raise `pubspec.yaml` to `1.0.2+3`, build and lineage-sign version 3 with
   the same `pilot_defines.json` (steps 2–5 of the release procedure), and
   archive it under a new name.
3. Write `payload.json` for version 3 (its exact size and SHA-256,
   `apkUrl` `.../app-releases/dokan_pro_3.apk`) and sign it with the tool.
4. Upload `dokan_pro_3.apk`; check `curl -sI` (200, exact
   `content-length`) and re-download + SHA-256. Only then publish the
   manifest as `app-releases/manifest.json`.
5. Bring version 2 to the foreground or tap *Check for updates*: dialog
   1.0.1 → 1.0.2. Run the checks in "Two-version in-place upgrade test"
   (Later, cancel, airplane mode, complete, data intact, negative cases).
6. Only after that passes: one supervised update of the Samsung tablet,
   sync chip **Synced** first.

Not yet done: none of steps 1–6. Nothing has been installed, uploaded or
published, and no in-app upgrade has been tested.

## Status (2026-10-16)

* Bucket `app-releases` exists and is public; `manifest.json` is absent
  (`NoSuchKey`).
* `pilot_defines.json` carries the four `APP_UPDATE_*` values (production
  host, HTTPS manifest URL, RSA-3072 public key, exponent `AQAB`).
* Built `C:\Users\ansar\.dukaan\apk\dokan-pro-1.0.1-2-updater-enabled-release.apk`
  (`com.dukaanpro.dukaan_pro`, versionCode 2, 121,637,993 bytes, SHA-256
  `6ecbec6245007b4ae89593b054056adfb99e989c53aa4cacf414f3f59fcf8eab`):
  v2 debug signer `3c0612…efd7b3`, v3 release signer `8ac9097e…d0441b` with
  the debug → release lineage. Manifest URL, host and public key are
  embedded in `libapp.so` for all ABIs; no private key material in the APK.
* The earlier `dokan-pro-1.0.1-2-release.apk` has the updater **off**
  (no manifest URL/key compiled in) and is kept only as a record.
* **Not yet tested on any device.**
