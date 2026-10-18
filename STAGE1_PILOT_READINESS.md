# Dukaan Pro — Stage 1 Pilot Readiness (Ali_shop, Galaxy Tab A9+)

Date: 2026-10-11 · Branch: `r1/sync-reliability` (uncommitted) · Scope: critical
fixes and validation only. No cloud, migration, manifest, APK, commit or push
changes were made.

## 1. Confirmed defects and root causes

| ID | Sev | Defect | Root cause | Status |
| --- | --- | --- | --- | --- |
| IMG-1 | P0 | Images missing on a device other than the one where they were picked | By design, photos are stored only in `<app support>/product_images/<id>.jpg` on the picking device. Nothing is uploaded, and `image_path` is never written. | **Open: needs cloud Storage** (design ready) |
| IMG-2 | P0 | A synced Storage key always shows the placeholder | `product_thumbnail_provider_native.dart` treats any non-http path as a local file. There is no Storage resolver and no bucket. | **Open: needs cloud Storage** |
| IMG-3 | P2 | `http(s)` image URLs are not cached to disk, so they are lost offline after a restart | `Image.network` uses a memory cache only | Not fixed (see §4) |
| PRN-1 | P0* | No thermal printing | Only `UnavailableReceiptPrinter` exists. No transport, plugin or permissions. | **Open: new feature** (plan ready) |
| INV-1 | P1 | One sale with repeated lines of the same product could oversell when negative stock is off | `LocalSaleService` compared each line, not the per-product total, with stock | **Fixed** |
| RCP-1 | P2 | Receipt had no unit prices and no discount line | `ReceiptModel` did not carry the stored `discount_total`, and the view did not show unit prices | **Fixed** |
| SEC-1 | P1 | The unencrypted SQLite database and images are included in Android cloud backup and device transfer | `backup_rules.xml` / `data_extraction_rules.xml` exclude only `sharedpref` | **Open: needs approval** (§6) |

\*PRN-1 is P0 only if the pilot requires paper receipts.

**Same-device versus cross-device images (item 7).** An image picked on the
Tab A9+ **should** show immediately and survive a restart. The code path
checks out:

- The product id returned by `create_custom_shop_product` / `create_shop_product` equals the client-minted id that the POS catalog uses.
- The file is written atomically.
- The store is indexed at startup before `runApp`.
- The image cache is cleared on save.

New tests prove that an image saved on this tablet renders after a restart,
via the real `DriftPosCatalog` product id. **If images picked on the A9+
itself are missing, that is a different, unexplained defect**, and §9 step
A3 isolates it. Images picked on any other device (desktop build, another
tablet, or before an uninstall or clear-data) are IMG-1. Cloud Storage
explains IMG-1/2 only.

## 2. Fixes implemented and changed files

| File | Change |
| --- | --- |
| `lib/features/sales/application/local_sale_service.dart` | INV-1: sums quantity per product across the sale before the stock check. The negative-stock rule itself is unchanged. |
| `lib/features/receipts/receipt_model.dart` | RCP-1: new `discount` field (the stored `discount_total`, default 0) |
| `lib/features/sales/sales_history.dart` | RCP-1: passes the stored discount into the receipt |
| `lib/features/pos/pos_workspace.dart` | RCP-1: one added line, `discount: stored.discount`. **This file also holds the user's pre-existing, uncommitted keyboard-focus changes, which were preserved.** |
| `lib/features/receipts/receipt_view.dart` | RCP-1: `@ Rs X each` / `@ Rs X/kg` under each line. `Discount -Rs X` appears only when the discount is above 0. |
| `test/stage1_regressions_test.dart` | New: 11 regression tests (INV-1, RCP-1, images) |
| `docs/stage1/storage-image-design.md` | New: Storage design (design only) |
| `docs/stage1/thermal-printer-plan.md` | New: ESC/POS integration plan (plan only) |
| `STAGE1_PILOT_READINESS.md` | This report |

No financial calculation was changed. The receipt shows only stored values.

## 3. Automated test results

| Suite | Target | Result |
| --- | --- | --- |
| `flutter analyze` | — | **PASS**: no issues |
| `flutter test` (full) | in-memory / temp files | **PASS**: 299 passed, 1 skipped (baseline 288 + 11 new) |
| `test/stage1_regressions_test.dart` | in-memory | **PASS** 11/11. Without the INV-1 fix, the 4 repeated-line tests fail. |
| R1 guard / tz ×3 / green | local Drift | **PASS** 15 / 3 / 101 |
| R1 direct-DB | scratch DBs `r1_direct_*` in the local container | **PASS** 65 |
| R1 HTTP | disposable stack on `127.0.0.1:54421`, scratch DB `r1_http` | **PASS** 38 |
| R1 timestamps and void matrix (UTC, Asia/Karachi, EST5) | local | **PASS** 20 + 9 per zone |
| Expected-red gate | — | 0 (suite empty) |
| Raw SQL security (`scripts/run_raw_sql_tests.ps1`) | local `supabase_db_POS_store`, 12 files, each `begin…rollback` | **PASS** 12/12 |
| pgTAP (`supabase test db --local`) | local, 6 files | **PASS** 98/98 |

Target safety:

- I confirmed every server test was local before running it: the Docker container, a loopback port, and a guard that refuses non-loopback hosts.
- Scratch databases and containers were removed afterwards. The local database list is unchanged.
- No database was reset.

## 4. Offline and sync correctness

These items have automated evidence, using local Drift plus the local server
over the direct-DB and HTTP layers: online and offline sale, multiple offline
sales, restart after commit, upload while the network drops or the response
is lost, retry with backoff, duplicate delivery (the server answers
`already_synced`, adding no duplicate sale or payment), lease contention
between two workers, a 15 s RPC timeout, `needsAttention` / `blockedAuth`
status, record-and-flag for offline Udhaar over the credit limit, void
convergence, server-owned pull order, and integer-paisa totals and stock after
pull (movements upsert by id, so they are never double counted).

No sync defects were found.

Note: there is no connectivity listener. After reconnecting, pending sales
upload on the next sale, on app resume, or within 2 minutes (periodic retry).
This is acceptable for a pilot.

IMG-3 was not fixed. The app writes no `http` image paths, and the Storage
design replaces URL-based images with a key-based local cache. Caching
expiring URLs now would be thrown away.

## 5. Inventory and accounting

The following are covered by existing tests plus the new INV-1 tests:

- PIECE whole-unit enforcement
- loose kg/g and L/ml in thousandths with exact rounding (`(price × qty + 500) ~/ 1000`)
- pack variants as independent products with independent stock
- returns, including cumulative partial returns of measured lines
- voids that restore stock and Udhaar
- Cash, Digital and Udhaar splits that must equal the total exactly
- the Udhaar credit limit
- refusal of negative stock when prohibited, now across repeated lines

The cart already merged lines per product, so INV-1 was not reachable from
the current POS screen. It is hardening at the service boundary.

## 6. Security

- **Covered:**
  - owner and cashier separation
  - device credential boundary (the HTTP test confirms the device credential reaches no owner operation)
  - cross-shop isolation
  - cashiers blocked from price and inventory changes
  - RLS and privileges (raw SQL 12/12, pgTAP 98/98, HTTP device boundary)
- **On-device secrets:** the owner session, device credential, cashier session and owner lock are in `flutter_secure_storage`. There is no PIN or PIN hash locally.
- **SEC-1:** `dukaan_pro.sqlite` is **plain SQLite, not encrypted. There is no database key.** It holds customer names and phones, Udhaar balances, sales and the sync queue, in `files/` (app support). Android Auto Backup and device-to-device transfer currently include it, and `product_images/`. Restoring onto another tablet brings back the data and pending queue but not the device credential, which is excluded. Pending operations would then be blocked or need attention under a new device identity until resolved: no data loss, but manual recovery. Restore on the same device (reinstall) is safe because uploads are idempotent.
  - **Recommended policy (needs approval):** exclude `file/dukaan_pro.sqlite*` (plus `-wal`/`-shm`) and `file/product_images/` from both `cloud-backup` and `device-transfer`. The server is the system of record. Before uninstalling or replacing a tablet, staff must confirm the sync chip shows *Synced*. Revisit if a database encryption key is ever introduced; any such key must also stay out of backups.

## 7. Receipt and printer

- On-screen receipt verified by tests: shop, phone, address, reference, date and time, cashier, customer, PIECE and loose units (2.5 kg, 750 ml), pack labels, unit prices, subtotal, discount (only when stored), total, returned/net, payments, received and change, footer.
- The 58 mm and 80 mm options exist only as an enum. There is no layout difference.
- Urdu: not supported for printing.
- Bluetooth/USB: not implemented. The Print button always says no printer is configured. **No printer compatibility is claimed.** See `docs/stage1/thermal-printer-plan.md`.

## 8. Remaining P0 blockers

1. **IMG-1/2:** cross-device product images need the Storage design to be approved and built. *Workaround for the pilot:* pick product photos on the Tab A9+ itself.
2. **PRN-1:** no thermal printing. It is a blocker only if paper receipts are required. *Workaround:* on-screen receipt.
3. **Physical verification not yet done:** none of §9 has been run on the tablet.
4. **SEC-2: local SQLite is unencrypted** (confirmed in Stage 1C, see the addendum). This is an **unresolved security blocker for real-customer rollout**. It is accepted for the controlled Ali_shop pilot only. Encryption and its migration are not attempted in Stage 1.

## 9. Physical tablet checklist (Ali_shop, Tab A9+)

These need the **tablet**; items marked 🌐 also need the **live network**, and 🖨 needs a **printer**.

**A. Images**
1. Settings → App info → confirm the build. Open Products and note which products show photos.
2. Owner mode: create a test product with a photo on the A9+. It should show in Products and on the POS grid immediately.
3. Force-stop the app and reopen it. The photo should still show. **If it doesn't, stop and report: that is a same-device defect, not IMG-1.**
4. Airplane mode, restart the app. The photo still shows.
5. A product whose photo was added on another device shows the placeholder (expected IMG-1). No crash, and billing works.

**B. Offline checkout and sync** 🌐
1. Online PIECE sale → chip reaches *Synced* within about 15 s.
2. Airplane mode → 3 sales (PIECE, 750 g loose, one pack size) → chip shows *Pending*, receipts open, stock drops locally.
3. Force-stop and reopen while offline → the 3 sales are in Bills, still *Pending*.
4. Turn the network back on → within 2 minutes (or open and close the app) → *Synced*. Owner dashboard totals = sum of receipts, to the paisa.
5. Start a sale sync, toggle airplane mode mid-sync → no error dialog during checkout. After reconnecting → *Synced*, with no duplicate in owner reports.
6. Compare stock for the sold products on a second device or owner screen after pull.

**C. Inventory and accounting**
1. Shop with negative stock off: product with stock 1 → selling 2 is refused.
2. Loose: 1.25 kg at Rs 130/kg = Rs 162.50. 750 ml at Rs 175/L = Rs 131.25.
3. Pack sizes: selling the 250 g size leaves the 500 g stock unchanged.
4. Return part of a loose line, and void a Udhaar sale → stock and customer balance restore.
5. Udhaar sale above the credit limit is refused online.

**D. Security** 🌐
1. Cashier mode: no access to products, prices, stock adjustment, reports or settings.
2. Owner revokes the device or cashier → the next sync and login are refused and sales stay queued.
3. Cashier session timeout behaves as configured.

**E. Receipt / printer** 🖨
1. After a sale with a line discount, the on-screen receipt shows unit prices, `Discount -Rs X` and the correct total.
2. Print shows "No receipt printer is configured". Expected; there is no printer support.

## 10. Recommendation

**NO-GO** for a controlled single-shop pilot **as of today**. There is no
physical-device evidence yet (§9 not run), and two P0 items are open
(IMG-1/2 cross-device images; PRN-1 if paper receipts are required).

**Conditional GO** is supportable once all of these hold:

- (a) §9 A–D pass on the Tab A9+, with A3 passing explicitly.
- (b) Ali_shop accepts photos added on the A9+ only, and on-screen receipts only.
- (c) A decision is recorded on SEC-1.

The automated evidence for sync, accounting and server security is strong
and complete for this stage.

---

## Addendum: Stage 1C (2026-10-11)

### Database encryption discrepancy: the database is NOT encrypted

The claim that "Drift with sqlite3mc encryption" was implemented is not
supported by the code, the history or the shipped binary.

| Check | Evidence |
| --- | --- |
| Runtime open path | All 8 `AppDatabase.open()` call sites use `NativeDatabase.createInBackground(File('<app support>/dukaan_pro.sqlite'))` (`lib/database/app_database.dart:48-55`). There is no `setup:` callback, no `PRAGMA key`, and no key lookup. |
| Build configuration | `pubspec.yaml` has no `hooks: user_defines: sqlite3: source: sqlite3mc`. `sqlite3 3.5.2` is a transitive dependency with the default (plain SQLite) source. There is no sqlcipher or sqlite3mc package. |
| Git history | `git log --all -S sqlite3mc`, `-S "PRAGMA key"` and a grep of commit messages for encrypt/sqlcipher/sqlite3mc: **no results on any local or remote branch.** |
| Shipped binary (previous `app-debug.apk`, 2026-10-11 12:25) | `lib/arm64-v8a/libsqlite3.so` is plain **SQLite 3.53.4**. It exports no `sqlite3_key`, `sqlite3_rekey` or codec symbols, and contains no sqlite3mc, Multiple Ciphers, ChaCha20 or SQLCipher markers. |
| Encryption key | None exists. Secure storage holds only the owner session, device credential, cashier session, owner lock and entitlement. |
| Tests | No encryption tests exist anywhere in `test/`, `test_r1/` or `supabase/`. |
| Project's own audit | `docs/recovery/forensic-audit-2026-09-30.md` S-4: "Local SQLite unencrypted; Android backup not disabled". It is planned for R2 and still open. |
| Backup exposure | `android:allowBackup` is unset (default true). The rules exclude only `sharedpref`, so `files/dukaan_pro.sqlite` (plus `-wal`/`-shm`) and `files/product_images/` are included in Google cloud backup and device-to-device transfer, **in plaintext**. A restore onto another tablet brings back the data but not the device credential (see §6). |

Nothing was changed. Encryption needs a design: a key in Android Keystore via
secure storage, a one-time plaintext-to-encrypted migration of existing
tablets, and backup exclusion. Implementing it needs your approval.

### Physical tablet checklist: Stage 1C (Ali_shop)

These are manual steps. Record a pass or fail and a screenshot for each.

**Before you start:** owner login, Wi-Fi on, sync chip shows *Synced*. Note the
stock of the test products, and the Udhaar balance of one test customer.

**A. Images**
1. Owner → Products → create a test product (PIECE, stock 10) with a gallery photo. It should appear in Products and on the POS grid at once. ☐
2. Close the app from Recents, then reopen. The photo should still show. ☐ (If not, report it: this is a same-device defect, not IMG-1.)
3. Wi-Fi off, close and reopen the app. The photo still shows, and the POS search and grid work. ☐

**B. Sales** (Wi-Fi on)
1. PIECE ×2. Stock goes down by 2. ☐
2. Loose 2.5 kg, receipt `2.5 kg × …`. Total = kg price × 2.5, exactly to the paisa. Stock goes down by 2.5 kg. ☐
3. Loose 500 ml. Total = price per L ÷ 2. Stock goes down by 0.5 L. ☐
4. Pack variant: pick one size. Only that size's stock goes down by 1; the other sizes are unchanged. ☐
5. On each receipt, `@ Rs … each` / `@ Rs …/kg` / `@ Rs …/L` appears under every line. ☐

**C. Offline**
1. Wi-Fi off. Make 2 sales; both receipts show and the chip shows *Pending*. ☐
2. Close the app from Recents and reopen it, still offline. Both sales are in Bills and still *Pending*. ☐
3. Wi-Fi on. Within 2 minutes (or switch away and back to the app) the chip shows *Synced*. ☐
4. Bills shows each sale exactly once, and today's totals = the sum of the receipts. ☐

**D. Accounting**
1. Sale with a line discount. The receipt shows Subtotal, `Discount -Rs X` and Total = Subtotal − X. ☐
2. Sale without a discount. No Discount line. ☐
3. Return part of a sale. Stock comes back by the returned quantity, and the refund equals the returned value. ☐
4. Udhaar sale to the test customer. Their balance goes up by the sale total. Void that sale: stock and balance go back to their earlier values. ☐
5. Cash sale. Today's cash total goes up by exactly the sale total. ☐

**E. Security**
1. Cashier mode: there is no way to create or edit products, change prices, adjust stock, see reports, or open settings. ☐
2. Every product, customer and bill shown belongs to Ali_shop only. ☐
3. Switching from cashier back to owner requires the owner unlock. ☐

**Optional cloud read (needs your explicit approval, read-only, run by you):**
check that the number of today's Ali_shop sales on the server equals the
number of bills on the tablet.

### Stage 1C pilot build (debug, not installed)

| Item | Value |
| --- | --- |
| Config | `C:\Users\ansar\.dukaan\pilot_defines.json`: valid; 5 defines present; `APP_ENV=pilot`; hosted `https://<ref>.supabase.co`, the same project as the previous pilot APK; the key is the public **anon** JWT (role anon, ref matches, not sb_secret or service_role, expires 2036); the RSA 2048-bit modulus and exponent 65537 match `pilot_entitlement_public_jwk.json` (public-only JWK, RS256) |
| Command | `flutter build apk --debug --dart-define-from-file="C:\Users\ansar\.dukaan\pilot_defines.json"` |
| APK | `build/app/outputs/flutter-apk/app-debug.apk`, 194,974,030 bytes, built 2026-10-11 19:51 |
| SHA-256 | `bd27414e3bde2a837ca9e111eb9f38416db89c71371772f0d212e4d99995e925` |
| Package | `com.dukaanpro.dukaan_pro`, versionCode 1 / 1.0.0, targetSdk 36, debuggable |
| Signer | Android Debug, cert SHA-256 `3c0612…efd7b3` (v2): **the same key as the previous pilot APK**, so it installs as an in-place update and keeps app data |
| Previous APK (rollback) | Copy kept in the session scratchpad. SHA-256 `f5fa1391e139cb4bf2b1adafec3116d56aa813e7c918c2e7e3b6effbdddcdc38` |
| Contents verified | Defines embedded. INV-1, RCP-1 and the keyboard-focus code present. `libsqlite3.so` is identical to the previous build (plain SQLite, as expected) |
| Checks | `flutter analyze` clean; `flutter test` 299 passed, 1 skipped (code unchanged since that run) |
