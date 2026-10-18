# Dukaan Pro — Project Audit (2026-10-12, pilot update 2026-10-13)

Branch `r1/sync-reliability` · HEAD `45b92b5` plus the existing uncommitted
Stage 1B / Stage 2 work (58 modified and ~25 untracked files), which was
preserved. Nothing was committed, stashed, pushed, deployed or migrated.

Evidence labels used below:

- **Code** – established by reading the exact lines cited.
- **Test** – reproduced or proven by a test that was run in this audit.
- **Estimate** – derived from stated assumptions; not measured.

---

## 0. Pilot preparation update (2026-10-13): current status

This section is the current status. It supersedes the status columns of §4
where they differ; §4.3 rows SEC-1, B-1, B-2 and B-11 are updated to match.
The "never oversell" rule (`lib/features/sales/domain/stock_policy.dart`) is
unchanged.

### 0.1 Fixed or completed in this pass

| ID | What changed | Evidence |
| --- | --- | --- |
| B-11 | **Not a defect.** The HTTP layer passed 38/38 *before* any change; my earlier prediction was wrong. `ServerShop.openingStock` was raised from 10 to 1,000 units for headroom (`test_r1/support/http_stack.dart`). The free bag is created through the owner RPC, which always tracks stock, so it stays a tracked zero-price product with opening stock. The direct-DB fixture's free bag has no stock and is untracked on both sides (A-10) | HTTP 38/38 before, 48/48 after (with the new tests) |
| P-1 (new) | **Return and void were confirmed only after network sync.** `sales_management_native.dart` awaited `SyncWorker.runOnce()` (up to 10 uploads × 15 s) before saying "saved locally". During that wait the owner could reopen the bill and enter the same return again (local checks only stop it exceeding the quantity sold). It now confirms right after the local commit and uploads in the background | Code; analyzer clean; existing Bills/Khata l10n widget tests pass. No new widget test: that screen needs a Supabase client and a file database; covered by tablet check D2 |
| Exactly-once | Sale, return, void and Khata payment verified over **real HTTP** (§0.2). No defect found; 10 regression tests added (`test_r1/http/exactly_once_http_test.dart`) | 10/10 |
| SEC-1 | `backup_rules.xml` (Android 7–11) and `data_extraction_rules.xml` (12+, both cloud backup and device transfer) now exclude `file/dukaan_pro.sqlite`, `-journal`, `-wal` and `-shm`, besides `sharedpref`. The path was checked: `path_provider_android` maps app support to `Context.getFilesDir()`. Product photos stay in the backup: not personal data, and the only off-tablet copy until IMG-1. No data on the device is touched | `test/android_backup_rules_test.dart` 4/4; rules present in the built APK (§0.10) |
| SEC-2 | Encryption assessment, migration and key-recovery plan: `docs/stage1/sec2-local-db-encryption-plan.md`. Not implemented. Also found: **the approved pilot build is debuggable**, so `adb run-as` can copy the database from an unlocked tablet with USB debugging on | Code |
| B-1 | Migration `supabase/migrations/202610130001_customer_ledger_sale_index.sql` added and measured (§0.3). **Not deployed** | Local plans below |
| B-2 | Limits confirmed. Bilingual warnings (English and Urdu) above the sale grid and under the Udhaar customer picker when a list is cut. Counts are taken only when a list is full | `test/audit_regressions_test.dart` B-2 ×4 (including Urdu) |

### 0.2 Timeout and retry: each financial operation applied exactly once

Server guard (Code): `sync_sale_transaction`, `sync_sale_return`,
`sync_sale_void` and `sync_customer_payment` each take a
`pg_advisory_xact_lock` on the sale id (sale, return, void) or the ledger
entry id (payment). They then return `already_synced` for an identical replay
and `DPC01` for a different one. The device re-sends the stored payload
unchanged, and `SyncWorker` cuts each upload at 15 s (A-5); a timed-out
operation is retried with backoff.

Over the real Kong/PostgREST/GoTrue path:

| Scenario | Sale | Return | Void | Khata payment |
| --- | --- | --- | --- | --- |
| Local commit, then the response is lost after the server committed; retry → one copy on the server, op `synced`, payload unchanged | ✅ | ✅ | ✅ | ✅ |
| The same payload uploaded twice at once (original still running when a retry starts) → `inserted` + `already_synced`, one copy | ✅ | ✅ | ✅ | ✅ |
| Two sync runs racing on one device's queue → each op uploaded once (4 sales) | ✅ | — | — | — |
| Void queued offline behind its sale → never attempted first; both then sync once | — | — | ✅ | — |

What the UI reports after a local commit:

| Operation | Message |
| --- | --- |
| Sale | Receipt opens immediately with the sync chip *Pending* (R1.1) |
| Khata payment | "Payment saved locally and queued for sync" at most 15 s after commit; the button is disabled until then (A-4) |
| Return / void | "saved locally" immediately (P-1) |

A failure *before* the commit is the only path that shows "could not be
saved/recorded".

### 0.3 B-1: measured, and how to deploy

Measured on a disposable local database: 1,000 shops; 10,000 customers;
**1,000,000** ledger rows (70% Udhaar sales with `sale_id`, 30% payments); a
329 MB table; local Supabase Postgres in Docker.

| | Plan | Time | Buffers |
| --- | --- | --- | --- |
| Before | Parallel Seq Scan over 1M rows | **116.7 ms** per sale upload | 17,643 (15,603 read from disk) |
| After migration | Index Scan `customer_ledger_entries_sale` | **0.07 ms** | 4 |

- **Index build:** 1.7 s (plain `CREATE INDEX` inside the migration). Index size: 21 MB.
- **Full chain:** all 24 migrations from zero passed in the HTTP stack, the direct-DB layer (65/65), raw SQL (12/12) and pgTAP (98/98).
- **5M-row repeat:** attempted, but it filled drive D: (see §0.6), so it was not completed.

**When it matters (Estimate):** cost grows linearly with *total* ledger rows
across all shops, about 0.12 ms per 1,000 rows on this machine, and it burns
CPU/IO for every tenant. Assume about 70 ledger rows per shop per day (20% of
300 daily sales on Udhaar, plus repayments). Then 1M rows ≈ **40 shop-years**
(e.g. 40 shops for one year, or 480 shops for a month). The earlier "before
50 shops" figure is not supported by a measurement; treat it as a rough
estimate. The index is cheap, so ship it with the next server migration
regardless.

**Deployment (production, after the pilot APK is accepted):**

1. Confirm a recent backup or point-in-time recovery for the project.
2. At low traffic, in the SQL editor or `psql`, **outside a transaction**: `create index concurrently if not exists customer_ledger_entries_sale on public.customer_ledger_entries (sale_id) where sale_id is not null;`
3. Verify it is valid: `select indisvalid from pg_index where indexrelid = 'public.customer_ledger_entries_sale'::regclass;` must be `true`. If `false`, run `drop index concurrently public.customer_ledger_entries_sale;` and repeat step 2.
4. Apply the migration with the normal process (`supabase db push`). It is `create index if not exists`, so it only records the migration.
5. Spot-check `explain select sum(amount) from public.customer_ledger_entries where sale_id = '<real sale id>' and type = 'creditSale';` → Index Scan.
6. **Rollback:** `drop index concurrently if exists public.customer_ledger_entries_sale;` No data or function depends on it.

### 0.4 B-2: affected workflows and the proper fix

**Limits:** the POS loads at most 5,000 active products and 1,000 active
customers, alphabetically (`posProductLimit`, `posCustomerLimit` in
`pos_catalog.dart`).

| Workflow | Past the limit |
| --- | --- |
| Sale grid, search, pack-family cards | Product is not shown or found |
| Barcode scan (`submitBarcode`) | "No product matches that barcode" |
| Udhaar customer picker (payment dialog) | Customer cannot be picked |
| Khata screen | **Not affected**: SQL search, 500 matches per query, narrowed by typing |
| Owner Products / Customers screens | Not affected (own queries) |

**Now:** an orange warning above the sale grid ("Showing the first 5,000 of N
products…") and under the Udhaar picker, in English and Urdu. Counts are only
queried when a list is full, so normal shops pay nothing.

**Proper fix** (R5; when any shop passes about 3,000 active products or 700
customers):

1. Barcode lookup as an indexed query, `shop_products(shop_id, barcode)`, which already exists.
2. Search as a SQL `LIKE` over name, plus barcode with `LIMIT 100`, debounced, instead of filtering an in-memory list. The grid shows the first page plus favourites.
3. The Udhaar picker becomes a search field over `DriftCustomerRepository.search`.
4. Stock via the projection table from B-3, so each page is cheap.
5. Validate with 20,000 products and 5,000 customers: scan and pick the last of each, with search latency under 100 ms on the Tab A9+.

### 0.5 Unsynced transactions if a tablet is lost

They exist only on that tablet until uploaded. Since SEC-1 they are not in
Google backup either, and they were never recoverable from a backup on
another tablet without manual work. Controls:

- the sync chip must show *Synced* before closing, handing over, updating or uninstalling;
- automatic retry every 2 minutes and on resume;
- the owner deactivates a lost device, which stops its credential at once.

Details: `docs/stage1/sec2-local-db-encryption-plan.md` §6.

### 0.6 Incident during this pass: disk full

The 5M-row B-1 benchmark filled drive **D:**, which also holds Docker's disk
image (`D:\DockerData`) and this repository. What happened:

1. Postgres in `supabase_db_POS_store` panicked (`could not fdatasync`) and Docker's VM filesystem went read-only.
2. With your approval I:
   - restarted Docker/WSL (`wsl --shutdown`); Postgres crash recovery completed cleanly;
   - checked the dev database: 23 migrations, 34 tables, unchanged;
   - dropped only my scratch databases;
   - pruned unused Docker images (9.5 GB freed *inside* Docker's disk).
3. I deleted only Flutter's regenerable test caches in `build/` (~770 MB).

Before the restart, the previous APK was copied to C: (§0.10).

**D: still has only about 570 MB free**, because Docker's disk image does not
shrink by itself. Full tests and the APK build therefore ran from an exact
snapshot of the working tree on C: (byte-compared before building). **Please
free several GB on D:** before further Docker or build work.

### 0.7 Remaining pilot blockers

1. **Physical tablet run not done** (§0.9).
2. **IMG-1/2**: photos do not cross devices. The workaround is to add photos on the pilot tablet; it needs your written acceptance.
3. **PRN-1**: no thermal printing. The workaround is the on-screen receipt; it needs your acceptance if paper receipts are expected.
4. **Debuggable pilot build** (SEC-2 doc §1). Accept it for a single controlled shop, or approve the release keystore and ship a release build.
5. **SEC-2 (encryption)**: accepted for the Ali_shop pilot only, as recorded in Stage 1; required before real-customer rollout.

### 0.8 Later scaling work (not needed for one shop)

| Item | When |
| --- | --- |
| Deploy B-1 | With the next server change |
| B-2 proper search | Around 3,000 products / 700 customers per shop |
| B-3 device stock projection and outbox pruning | Before about 6 months of busy history |
| B-4 periodic pull | Before multi-tablet shops |

The rest is in §9.

### 0.9 Checks that still need a physical device

- Everything in the checklist below, on the Galaxy Tab A9+.
- Backup exclusion on a real device: optional, with `adb shell bmgr backupnow com.dukaanpro.dukaan_pro` and then inspecting the transport.
- **Linux time-zone matrix (UTC, EST5): pending**; it runs only in CI on Linux. Windows ignores `TZ`, so only Asia/Karachi was exercised locally.

### 0.10 Verification and build (2026-10-13)

All results below are from runs in this pass. Flutter 3.44.1 / Dart 3.12.1 on Windows 11.

| Check | Where | Result |
| --- | --- | --- |
| `flutter pub get --enforce-lockfile` | C: snapshot | **PASS**: lockfile unchanged |
| `flutter analyze` | C: snapshot | **PASS**: no issues |
| `flutter test` | C: snapshot | **PASS**: 561 passed, 1 skipped (553 + 4 B-2 + 4 backup rules) |
| `flutter test test/stress_performance_test.dart --dart-define=RUN_STRESS=true` | C: snapshot | **PASS** 1/1 |
| `flutter test test_r1/guard` | C: snapshot | **PASS** 15/15 |
| `flutter test test_r1/tz --dart-define=EXPECTED_TZ_OFFSET_MINUTES=300` | C: snapshot | **PASS** 1/1 (host zone Asia/Karachi only) |
| UTC / EST5 time-zone matrix | — | **PENDING**: runs only on Linux (CI) |
| `flutter test test_r1/green` | C: snapshot | **PASS** 107/107 |
| `flutter test test_r1/direct_db --dart-define=R1_SERVER=true` | repo; scratch `r1_direct_*` DBs, all 24 migrations | **PASS** 65/65; database list unchanged afterwards |
| `flutter test test_r1/http` (before any B-11 change) | disposable stack `127.0.0.1:54421`, scratch `r1_http` | **PASS** 38/38 |
| `flutter test test_r1/http` (final, with B-1 migration and exactly-once tests) | same, rebuilt from zero | **PASS** 48/48 |
| Raw SQL security suites (the 12 files of `scripts/run_raw_sql_tests.ps1`) | scratch `r1_http` (24 migrations + seed), not the dev DB | **PASS** 12/12 |
| pgTAP (`supabase/tests`, 6 files, run with psql and `create extension pgtap`; Supabase CLI not installed) | scratch `r1_http` | **PASS** 98/98 |
| B-1 query plan before/after | scratch DB, 1M ledger rows | Seq Scan 116.7 ms → Index Scan 0.07 ms (§0.3) |

The C: snapshot is an exact copy of the working tree (427 files, byte-compared
with `cmp` immediately before the build). It was used because D: had no room
for test caches or a Gradle build.

**Pilot APK (built 2026-10-13 01:42):**

| Item | Value |
| --- | --- |
| Command | `flutter build apk --debug --dart-define-from-file="C:\Users\ansar\.dukaan\pilot_defines.json"` (the Stage 1C configuration) |
| APK | `C:\Users\ansar\.dukaan\apk\dukaan-pilot-2026-10-13-debug.apk` |
| Size | 172,007,797 bytes |
| SHA-256 | `847465d47ad20d1bd436d88a7d23c2251275dc7da3c6cd0e129dcd5b35c589ca` |
| Package | `com.dukaanpro.dukaan_pro` 1.0.0 (1), targetSdk 36, **debuggable** |
| Signer | Android Debug, cert SHA-256 `3c0612771a8ff9e2fce5dbacdab9ee3397821d5bf3b8e0abda1e40be3defd7b3`, identical to the previous and the Stage 1C APKs (in-place update keeps app data) |
| Contents | All 5 pilot defines embedded (`APP_ENV`=pilot). Both backup rule files carry the five exclusions; the manifest references them. New client code present |
| Size vs previous | 25 MB smaller. The previous file held ~24 MB of unreferenced bytes left by incremental packaging; entry contents match apart from the removed Cupertino font and +0.14 MB Dart code |

**Rollback copy:** `C:\Users\ansar\.dukaan\apk\dukaan-rollback-2026-10-12-debug.apk`,
196,896,457 bytes, SHA-256
`90de30b5c7bfc9d5128dfa2d2f42c1a5527616311f91c8782092183233f271ac`
(also still at `D:\POS_store\build\app\outputs\flutter-apk\app-debug.apk`).
Both hashes are in `SHA256SUMS.txt` beside them. Same signer, so rolling back
is `adb install -r` of the old file.

**Rollback limits:**

- Rolling back does not undo SEC-1, but nothing needs undoing: backup rules do not touch data.
- Only operations that have already synced are safe across any reinstall.

### 0.11 Tablet checklist (Ali_shop, Galaxy Tab A9+)

**Before you start:**
- Install with `adb install -r` over the current app; do not uninstall.
- Owner signs in.
- Sync chip shows *Synced*.
- Note the stock of 3 test products and the Udhaar balance of one test customer.
- Keep a second device (phone or PC) signed in as owner.

**A. Price change from another device (no restart)**
1. On the tablet, open the cashier sale screen and add product X to the cart (old price shows).
2. On the second device, change X's price.
3. On the tablet, press Home, then return to the app (resume). Or try to pay: the first payment is refused and the cart then shows the new price.
4. Pay again. The sale succeeds at the **new** price and the receipt shows it.

   > ⚠ Changes from another device reach the tablet only at app start (B-4, open). If the new price has not arrived after resume, close the app from Recents and reopen it, then repeat. **Record which of the two was needed.**

**B. Khata payment: rapid taps and airplane mode**
1. Customer with an Udhaar balance → Receive Payment → Rs 100 → **double-tap** Record Payment. Exactly **one** entry appears; the button greys out until it finishes.
2. Airplane mode on, receive Rs 50. "Payment saved locally and queued for sync" appears within about 15 s. Exactly one entry.
3. Toggle airplane mode off and on while a payment is saving. Still one entry.
4. Airplane mode off. Within about 2 minutes the chip shows *Synced*. On the second device, the customer has exactly these payments, once each.

**C. Offline sales, returns/voids, restart, reconnection**
1. Airplane mode on. Make 3 sales: piece, 750 g loose, one pack size. Receipts open; chip shows *Pending*.
2. Owner → Bills:
   - void one of these sales (within 15 min): "Sale void recorded locally" shows **immediately**;
   - make a partial return on another: "Return saved locally" shows immediately.
3. Force-stop the app and reopen it, still offline. All 3 sales, the void and the return are in Bills, still *Pending*.
4. Airplane mode off, then wait or resume. The chip shows *Synced*. On the second device each sale, void and return appears **once**. The void was not reported as a sync issue.

**D. Stock, ledger and receipt totals**
1. Stock moved by exactly the quantities sold, returned and voided (the voided sale's stock is back).
2. Udhaar balance = start + credit sales − payments − credit refunds.
3. Each receipt: unit price lines, Discount only when there is one, Total = Subtotal − Discount, payments add up to Total.
4. Today's total on the sale screen = sum of non-voided receipts minus refunds, as on the owner dashboard.
5. A product with stock 1: selling 2 is refused ("never oversell"). A product already below zero cannot be sold.

**E. Urdu / RTL, images, printing**
1. Switch to اردو:
   - sale screen, payment dialog, Khata, Bills and receipt read right to left;
   - amounts and quantities keep Western digits and read correctly;
   - nothing is cut off.
2. In Urdu, repeat one sale and one Khata payment. Messages are in Urdu.
3. Product photos added on this tablet still show after a restart and offline. A product with a photo from another device shows the placeholder (IMG-1, expected).
4. Print shows "No receipt printer is configured" (PRN-1, expected). The on-screen receipt is complete.

Record pass or fail and a screenshot for each step. Any duplicate entry, wrong
total or missing record is a **stop**: roll back and send the screenshots.

---

## 1. Overall assessment

The core is in good shape and much better than the 2026-09-30 forensic
baseline. Money is integer paisa and quantities are integer thousandths
everywhere. Every financial action is one local Drift transaction plus an
outbox row. Server RPCs are idempotent and fingerprinted. Tenant isolation
uses RLS and composite `(id, shop_id)` keys. R1 (checkout durability, void
identity, server-owned pull order, failure classification) is implemented and
heavily tested. Cashier mode now runs on a device credential, not the owner
session.

The problems that remain are mostly at the **edges of those contracts**:

- ordering between dependent outbox operations;
- the POS screen trusting a catalog snapshot that the database has moved past;
- UI paths that wait on the network after a local commit;
- one silent-truncation limit;
- one missing server index;
- Drift upgrade gaps for old snapshots.

The known pilot blockers from `STAGE1_PILOT_READINESS.md` still stand:

- cross-device images (IMG-1/2);
- thermal printing (PRN-1);
- the unencrypted, backed-up local database (SEC-1/SEC-2);
- no physical-tablet run yet.

### Five highest-priority findings

| # | ID | Sev | Finding | Status |
| --- | --- | --- | --- | --- |
| 1 | SEC-1/2 | High | Local SQLite (customers, Udhaar, sales, sync queue) is plaintext and included in Android cloud backup and device transfer | Open: needs your approval (pre-existing finding) |
| 2 | A-3 | Medium | POS keeps showing the old price after a background pull; checkout charges the new price, so the sale is refused and the item cannot be sold until some other sale succeeds | **Fixed** + tests |
| 3 | A-4 | Medium | Khata "Receive payment" can record a duplicate payment: no in-flight guard, and the screen waits on network sync after the local commit | **Fixed** + test |
| 4 | A-1 | Medium | A void or return can upload before its own sale; the server answers "original sale required" and after 5 attempts the record needs owner attention | **Fixed** + tests |
| 5 | B-1 | High at scale | Every sale upload runs `sum(...) where sale_id = ?` on `customer_ledger_entries`, which has no `sale_id` index: a sequential scan over every tenant's ledger | Open: needs a migration (SQL below) |

---

## 2. Project map (verified)

| Area | Summary |
| --- | --- |
| Stack | Flutter 3.44.1 / Dart 3.12.1; Drift (SQLite) v13 on device; Supabase (Postgres 17, PostgREST, GoTrue, one Deno edge function `issue-entitlement`); Android tablet is the target, and a web build exists only as stubs (`*_web.dart` conditional exports) |
| Entry | `lib/main.dart` → `LocalizedMaterialApp` → `DukaanProApp` → `AuthGate` → `CashierResumeGate` (device lobby / cashier) or `OwnerBootstrap` (owner screens) |
| Cashier flow | Cashier PIN login → `PosRuntime` (session-less client + `x-dukaan-device` credential) → `PosWorkspace` → `DriftPosSaleCommitter` → `LocalSaleService` (one transaction + outbox) → `SyncWorkerRunner` (background, 15 s RPC cut, 2 min retry timer, resume) |
| Owner flow | Dashboard, products, inventory, customers/Khata, suppliers/purchases, expenses, bills (returns, voids), settings, sync issues. Each screen opens its own Drift connection and uploads through `SyncWorker` |
| Sync up | `sync_operations` outbox → leased by `SyncQueueRepository.acquireLease` → RPC per aggregate. Failures are classified as connectivity / transient / auth / permanent / unknown (`sync_failure.dart`) |
| Sync down | `ReferencePullService` pages by `(server_seq, id)`. The owner uses table reads; cashier mode uses the `device_pull` RPC. The POS pulls only at start (O-3) |
| Server | 23 migrations. Security-definer RPCs, RLS on every table, stable `DP*` error codes, record-and-flag for the credit limit |
| CI | `.github/workflows/ci.yml`: gitleaks, analyze/test, fresh stack migrations + raw SQL + pgTAP, R1 harness (guard, TZ matrix, green, direct-DB, HTTP) |
| Docs | `docs/recovery/forensic-audit-2026-09-30.md` (roadmap R0–R8), `STAGE1_PILOT_READINESS.md`, `STAGE2_LOCALIZATION_PLAN.md` (English + Urdu RTL, implemented in the uncommitted work) |

---

## 3. Baseline (before any change)

| Command | Result |
| --- | --- |
| `flutter analyze` | **PASS**: no issues (170 s) |
| `flutter test --reporter expanded` | **PASS**: 544 passed, 1 skipped (opt-in stress test), 0 failed |

There were no pre-existing failures.

---

## 4. Findings

Severity reflects actual impact on a shop. "Confirmed" means it is shown by
code or a test; "Potential" means it needs measurement.

### 4.1 Correctness defects — fixed in this audit

| ID | Sev | Status | Where (before fix) | Trigger → impact | Fix and validation |
| --- | --- | --- | --- | --- | --- |
| A-1 | Medium | Confirmed (Code + Test), **fixed** | `local_sale_void_service.dart` and `local_sale_return_service.dart` never set `dependsOnOperationId`, although the queue supports it (`sync_queue_repository.dart:68-87`). The server's `sync_sale_void` / `sync_sale_return` raise `original sale required` (P0001, not mapped to a stable code), which is classified *unknown* | The sale upload fails with a 5xx or times out and enters backoff (up to 300 s). The void or return queued after it is due immediately, uploads first, fails as unknown, and after 5 attempts or 1 h becomes **needs attention**. The owner sees a sync issue for a valid record and must press Retry. Latent: a dependency whose parent row is missing would block forever (`parent?.status != synced`) | Void and return operations are now queued behind the sale's unsynced operation (`SyncQueueRepository.unsyncedOperationId`). A missing parent no longer blocks. Tests A-1 ×3 |
| A-2 | Low | Confirmed (Code + Test), **fixed** | `local_sale_void_service.dart:77-84` used `getSingleOrNull()` on `sale_returns` | Voiding a sale that has **two or more** returns threw `Bad state: Too many elements` instead of "A sale with returns cannot be voided." Nothing was written either way; the owner saw a generic failure | `limit(1)`. Test A-2 |
| A-3 | Medium | Confirmed (Code + Test), **fixed** | `pos_workspace.dart` reloaded the catalog only after a *successful* checkout (`_reloadCatalog`, called once). `pos_runtime_native.dart` started the background pull with `unawaited` and never told the screen. `LocalSaleService` prices lines from the database, not the cart | The owner changes a price on another device; the tablet starts from cache; the background pull applies the new price. The cashier rings the item at the old displayed price and checkout is refused ("Payment total must equal sale total"). Re-adding the item uses the same stale catalog, so **that item cannot be sold** until some other sale succeeds. The same happens for a product the owner deactivated | The workspace reloads the catalog when the startup pull completes (`catalogRefresh`), after any refused checkout, and on app resume. `PosCart.refreshProducts` re-binds cart lines to current prices and stock, so the cart shows what will be charged. Tests A-3 ×2 |
| A-4 | Medium | Confirmed (Code + Test), **fixed** | `customer_khata_view.dart`: the Receive Payment button had no in-flight guard. `drift_pos_sale_committer.dart:116-119` awaited a full `sync.run()` (up to 10 uploads × 15 s, plus re-runs). The owner variant awaited `SyncWorker.runOnce()` with **no** timeout | The payment is committed locally, then the screen waits on the network with no feedback. On a weak connection the cashier taps again and records a **second real payment** (allowed whenever it is still ≤ the balance) | The button is disabled while a payment is in flight. The cashier-side wait is capped at 15 s; the payment is already saved and the runner continues on its own. Test A-4 |
| A-5 | Medium | Confirmed (Code + Test), **fixed** | `SyncWorker.runOnce` had no RPC timeout. Only `SyncWorkerRunner` wrapped one. Six owner screens (`customer_`, `expense_`, `inventory_`, `product_`, `purchase_`, `sales_management_native.dart`) await `SyncWorker(...).runOnce()` directly | A hanging HTTP request (captive portal, half-open socket) held those screens' save or refresh indefinitely | `SyncWorker.uploadTimeout` (default 15 s; the runner passes its own `rpcTimeout`). A timeout is a connectivity failure and is retried with backoff. Test A-5 |
| A-6 | Low | Confirmed (Code), **fixed** | `pos_runtime_native.dart` Retry (`startup = _start()`) opened a new `AppDatabase` without closing the previous one | After a failed POS start, every Retry leaked a SQLite connection to the same file (risk of `database is locked`, memory growth) | `_start()` closes any previous connection first |
| A-7 | Low (perf) | Confirmed (Code), **fixed** | `pos_runtime_native.dart` loaded **every** `sync_operations` row of the shop (never pruned, each carrying its JSON payload) to compute the status chip. `LocalSaleService._stock` loaded every movement row of a product into Dart, per line, per checkout | POS start and checkout time grow with history (the forensic audit measured 10.1 s startup at 1-year volume) | Status uses the same filtered query as the live chip (unsynced plus unacknowledged flagged only). Stock is `SUM()` in SQL. Behaviour is unchanged; covered by the existing INV-1 and checkout tests |
| A-8 | Low | Confirmed (Code + Test), **fixed** | `parseMoneyMinor` (`pos_state.dart`), and the two duplicate `parseQuantity` helpers (`product_management_native.dart`, `purchase_management_native.dart`) accepted unbounded digit runs | 17+ digit money overflowed `int` (wrapped negative); 20+ digit quantities threw `FormatException` from a form validator | Capped at 12 rupee digits and 9 whole-unit digits (far above any real value; quantities above 1,000,000 units were already refused elsewhere). Test A-6 |
| A-9 | Low (data perf) | Confirmed (Test), **fixed** | `app_database.dart` `from < 9` used `m.createTable` for `sale_returns`, `sale_return_items` and `sale_voids`, which does not create their four `@TableIndex` indexes. Upgrade tests only started at v10 | A tablet first installed at Drift v7 or v8 has no index on the return/void lookups that run on every void, return and Bills detail view. A temporary probe (`migrateAndValidate` from v7 and v8) failed with "Schema does not match"; v9–v12 passed | `beforeOpen` creates the four indexes `IF NOT EXISTS`, batched into the one statement it already ran, so opening costs no extra round trip. This also repairs devices that already upgraded. A first per-statement version made 3 owner-screen widget tests fail, because the extra isolate round trips delayed the screen past the test's real-time wait; the batched version passes them. New permanent test: upgrade-and-validate from every snapshot v7–v12 |
| A-10 | Medium (CI) | Confirmed (Test), **fixed** | `test_r1/support/direct_db_server.dart` seeded 10 units of stock and an untracked-in-intent "Free bag" with tracking on. The uncommitted pilot rule `stock_policy.dart` (sales never oversell) makes `LocalSaleService` refuse those sales | 3 direct-DB tests failed with `Insufficient stock`. With the previous rule restored temporarily they passed 11/11, so the cause is the policy change, not the audit. **CI's direct-DB job would go red** as soon as the Stage 1 work is committed | Opening stock raised to 1,000 units (the same change already made in `pos_fixture.dart`). The free bag is untracked on both the server and device seed. Direct-DB: 65/65 pass |

### 4.2 Cleanup — done

| Item | Evidence it was unused | Action |
| --- | --- | --- |
| `lib/database/repositories/accounting_repository.dart` | No import in `lib/`, `test/`, `test_r1/`, `tool/` or docs. Its `productStock` used sign normalisation (`conventionalSign`), unlike every production stock query (raw signed sum): a contradictory second implementation | Deleted |
| `lib/sync/development_diagnostics.dart` | No import or reference anywhere | Deleted |
| `lib/sync/sync_service.dart` (`SyncService`, `OfflineOnlySyncService`) | No import or reference anywhere; superseded by `SyncWorker` / `ReferencePullService` | Deleted |
| `cupertino_icons` dependency | Zero `CupertinoIcons` / `package:cupertino_icons` uses; template default that bundles an unused font | Removed from `pubspec.yaml`; `pubspec.lock` updated by `flutter pub get` (only this entry changed) |

Kept on purpose: `lib/core/images/product_image_source.dart` is unused, but
`docs/stage1/storage-image-design.md:78` names it as the interface the
approved Storage design implements. Web stubs (`*_web.dart`) are platform
variants selected by conditional exports.

### 4.3 Open findings — not fixed (with concrete steps)

| ID | Sev | Status | Where | Why it matters | Recommended fix → validation |
| --- | --- | --- | --- | --- | --- |
| SEC-1 / SEC-2 (S-4) | High | **SEC-1 fixed 2026-10-13** (see §0); SEC-2 open | `backup_rules.xml`, `data_extraction_rules.xml`; `app_database.dart:48-55` opens plain SQLite | Before the fix, customer names, phones, Udhaar balances, sales and the outbox went to Google backup and device transfer in plaintext | SEC-1: the database and its companion files are now excluded on Android 7–11 and 12+ (§0.1). SEC-2 (encryption): plan in `docs/stage1/sec2-local-db-encryption-plan.md` |
| B-1 | High at scale | **Measured; migration added 2026-10-13** (see §0) | `202610080001_product_units_variants.sql:310` runs `select sum(amount) from public.customer_ledger_entries where sale_id = v_sale_id ...` for **every** sale upload | At 1M ledger rows (local 4 vCPU container) this query was a Parallel Seq Scan: 116.7 ms and ~17,600 buffers per sale upload | `supabase/migrations/202610130001_customer_ledger_sale_index.sql`. With it: Index Scan, 0.07 ms, 4 buffers. **Not yet deployed** (steps in §0.3) |
| B-2 | Medium | **Mitigated 2026-10-13** (see §0) | `drift_pos_catalog.dart` limits 5,000 products / 1,000 customers | Products past the limit cannot be searched, scanned or sold; customers past the limit cannot be picked for Udhaar | Bilingual warnings now show when either list is cut. The proper fix is in §0.4 |
| B-3 (P-2) | Medium | Confirmed (Code; forensic audit measured 9.6 s) | `drift_pos_catalog.dart:23-36` sums the whole `inventory_movements` history per product on every reload (after every checkout and now also after a refused checkout and on resume). `local_sale_service.dart:493` reads movements by `reference_id` and ledger rows by `sale_id`, both unindexed locally. `sync_operations` is never pruned | Device time grows linearly with shop age; a 1-year busy shop is in multi-second territory | R5: a per-product stock projection table maintained in the same transaction (or a covering index plus incremental refresh); local indexes on `inventory_movements(reference_id)` and `customer_ledger_entries(sale_id)` (Drift v14 with an upgrade test); prune synced operations older than N days. → a 1-year busy-shop fixture with budgets: checkout < 300 ms, start < 3 s |
| B-4 (O-3) | Medium | Confirmed (pre-existing) | `pos_runtime_native.dart` pulls only at start | Sales, stock and Khata changes from other counters are invisible until restart. With two tablets, one can oversell stock the other already sold (the server does not enforce stock) | Periodic pull (e.g. with the 2-minute retry timer) plus pull on resume, then `_reloadCatalog` (now wired). → a two-device direct-DB simulation |
| IMG-1/2, PRN-1 | P0 for pilot | Open (pre-existing) | `STAGE1_PILOT_READINESS.md` §1 | Photos do not cross devices; no thermal printing | Per `docs/stage1/storage-image-design.md` and `thermal-printer-plan.md`, or accept the documented workarounds in writing |
| B-5 | Low | Confirmed (Code) | `pos_runtime_native.dart:95-104` refreshes the entitlement with the device client; `entitlement_claims` requires `is_active_owner` (`202609200003_subscriptions_entitlements.sql:63`) | In cashier mode the refresh always fails: one wasted request per POS start, and up to **8 s** extra start time when the cached entitlement is not valid. A renewed subscription reaches the tablet only when the owner signs in | Skip the refresh in cashier mode, or add a device-credential path to `entitlement_claims`. → start the POS with an expired entitlement and time it |
| B-6 | Low | Confirmed (Code) | `supabase/functions/issue-entitlement/index.ts:17` returns `String(e)` with status 403 for every failure | Leaks internal error text (Postgres messages, missing env) to clients, and a misconfiguration looks like an authorisation failure | Map known errors to 401/403 with fixed messages, log the detail server-side, and return 500 for the rest |
| B-7 | Low (maintainability) | Confirmed (Code) | Test-only code in `lib/`: `sync/sale_sync_coordinator.dart` (an unleased upload path that retries forever, contradicting `SyncWorker`), `core/money/money.dart`, `features/customers/domain/customer_balance.dart`, `features/inventory/domain/inventory_calculator.dart`, `features/sales/domain/sale_totals.dart`, `database/repositories/shop_product_repository.dart` | Dead production code that encodes outdated contracts and invites reuse | Delete them with their foundation tests (`domain_foundation_test.dart`, parts of `phase_1_services_test.dart` and `database_foundation_test.dart`). Not done here because those test files carry your uncommitted edits |
| B-8 | Low (maintainability) | Confirmed (Code) | Two identical `parseQuantity` helpers (products, purchases); `formatPkr` duplicated (`STAGE2_LOCALIZATION_PLAN.md` §1) | Fixes have to be made twice (A-8 was) | Move them to `core/format` |
| B-9 | Low | Confirmed (Code) | `docs/recovery/status.md:6` still says "R1 … NOT STARTED"; `.github/workflows/ci.yml:36` floor `BASELINE_MIN_FLUTTER_PASSED: "95"` while 553 pass | The governance doc contradicts the history (R1.0–R1.6 committed). The CI floor no longer protects against silently dropped tests | Update `status.md`; raise the floor to the new count when this work is committed (`ci.md` says floors are raised when tests are added) |
| B-11 | — | **Not a defect** (Test, 2026-10-13) | `test_r1/support/http_stack.dart` seeded 10 units | Prediction was wrong: the HTTP layer passed 38/38 before any change, because no HTTP test sells more than 10 units | Opening stock raised to 1,000 units for headroom only; HTTP 48/48 |
| B-10 | Low | Potential risk | Server `sync_sale_return` allows a cash refund of an Udhaar (credit) sale and a credit refund larger than the credit portion (forensic audit "refund tender not validated") | The till pays out cash for goods never paid for, or Khata goes negative | Product decision: refund tender ≤ the original tender per method; enforce in `LocalSaleReturnService` and the RPC |

### 4.4 Areas reviewed with no new defect found

- Integer money and rounding (`lineTotalMinor`, `saleReturnRefund`, server mirrors).
- Checkout idempotency (`_checkoutIdFor`, `CheckoutConflict`).
- Lease and record-and-flag logic.
- Pull tenant validation (`_validateTenant`).
- `device_pull` column allow-lists.
- Device-credential hashing and the cashier-session proof.
- Grant hygiene in migration `202610070001`.
- Release signing guard in `android/app/build.gradle.kts`.
- `.gitignore` coverage of keys, databases and APKs.

Residual risk noted but not a defect: a device-credential holder can attribute a backdated sale to any cashier who once had a session on that device. The server trusts client timestamps, a known audit item (T17).

---

## 5. Changes made

| File | Change | Reason |
| --- | --- | --- |
| `lib/database/repositories/sync_queue_repository.dart` | `unsyncedOperationId()`; a missing parent no longer blocks a dependant | A-1 |
| `lib/features/sales/application/local_sale_void_service.dart` | Queue the void behind the sale's unsynced operation; `limit(1)` on the returns check | A-1, A-2 |
| `lib/features/sales/application/local_sale_return_service.dart` | Queue the return behind the sale's unsynced operation | A-1 |
| `lib/features/pos/pos_state.dart` | `PosCart.refreshProducts`; digit cap in `parseMoneyMinor` | A-3, A-8 |
| `lib/features/pos/pos_workspace.dart` | `catalogRefresh` parameter; reload after a refused checkout and on resume; re-bind the cart on reload | A-3 |
| `lib/features/pos/pos_runtime_native.dart` | Pass the startup pull to the workspace; close the previous DB on Retry; status from the filtered query | A-3, A-6, A-7 |
| `lib/features/pos/drift_pos_sale_committer.dart` | Cap the post-commit sync wait for a Khata payment at 15 s | A-4 |
| `lib/features/customers/customer_khata_view.dart` | `receiving` guard; button disabled while in flight | A-4 |
| `lib/sync/sync_worker.dart`, `lib/sync/sync_worker_runner.dart` | `uploadTimeout` on every upload (the runner passes `rpcTimeout`) | A-5 |
| `lib/features/sales/application/local_sale_service.dart` | `_stock` via SQL `SUM` | A-7 |
| `lib/features/products/product_management_native.dart`, `lib/features/purchases/purchase_management_native.dart` | Digit cap in `parseQuantity` | A-8 |
| `lib/database/app_database.dart` | `beforeOpen` creates the four v9 indexes `IF NOT EXISTS` | A-9 |
| `test/audit_regressions_test.dart` | New: 9 regression tests (A-1 ×3, A-2, A-3 ×2, A-4, A-5, A-6) | Regression coverage |
| `test_r1/green/drift_all_snapshots_upgrade_test.dart` | New: upgrade-and-validate from every snapshot v7–v12 | A-9 regression; fills the R4 gap |
| `test_r1/support/direct_db_server.dart` | Opening stock 10 → 1,000 units; free bag untracked | A-10 |
| Deleted `accounting_repository.dart`, `development_diagnostics.dart`, `sync_service.dart`; removed `cupertino_icons` | Proven unused | §4.2 |
| `PROJECT_AUDIT.md` | This report | — |

No server migration, RLS, Android manifest, backup rule or signing change was
made. No financial formula changed.

---

## 6. Verification

All commands were run on Windows 11 with Flutter 3.44.1 / Dart 3.12.1, after
the last code change unless a row says otherwise.

| Command | Result |
| --- | --- |
| `flutter analyze` | **PASS**: no issues |
| `flutter test` | **PASS**: 553 passed, 1 skipped, 0 failed (baseline 544 + 9 new) |
| `flutter test test/audit_regressions_test.dart` | **PASS** 9/9 |
| `flutter test test/stress_performance_test.dart --dart-define=RUN_STRESS=true` | **PASS** 1/1 |
| `flutter test test_r1/guard` | **PASS** 15/15 |
| `flutter test test_r1/tz --dart-define=EXPECTED_TZ_OFFSET_MINUTES=300` | **PASS** 1/1. This only checks the host zone (Asia/Karachi). Windows ignores `TZ`, so the UTC and EST5 matrix was **not** exercised; CI runs it on Linux |
| `flutter test test_r1/green` | **PASS** 107/107 (101 + 6 new snapshot-upgrade tests) |
| `flutter test test_r1/direct_db --dart-define=R1_SERVER=true` | **PASS** 65/65 after A-10. Scratch `r1_direct_*` databases in the local `supabase_db_POS_store` container; the list of databases was identical before and after. Before A-10: 62 passed, 3 failed (`Insufficient stock`); attributed by temporarily restoring the old oversell rule (11/11 passed), then restoring `stock_policy.dart` byte-identical (`cmp`) |
| `flutter test test_r1/http` | **BLOCKED**: needs a disposable local HTTP stack and `R1_HTTP_URL`/`R1_HTTP_ANON_KEY`; running it against the dev stack would write sign-ups into it. See B-11 |
| Raw SQL suites, pgTAP, migrations from zero | **NOT RUN**: no server SQL was changed in this audit, and the Supabase CLI is not on `PATH` |
| `flutter pub get` | Lock change limited to removing `cupertino_icons` |

How the regression tests prove the fixes:

- **Run against the fixed code and passing:** A-1 to A-6 (9 tests) and A-9 (6 tests).
- **Observed failing before the fix:** only A-9 (v7 and v8 failed in the probe).
- **Fail without the fix by construction, not by an observed run:**
  - A-1: no dependency is set, so the void is leased;
  - A-2: `Too many elements`;
  - A-3: the parameter and method did not exist;
  - A-4: the button stays enabled;
  - A-5: the hanging gateway never completes, so the test times out;
  - A-6: 13 digits parsed to a number.

**Still needs a device or the real environment:**

- the physical checklist in `STAGE1_PILOT_READINESS.md` §9 plus the two checks in §7;
- the HTTP layer;
- server SQL suites in CI;
- the A-3 behaviour on a real tablet after a real pull;
- the effect of A-9 on a tablet that actually started at v7/v8 (none is known).

---

## 7. Before the next release or pilot (necessary)

1. **Decide SEC-1 now.** Excluding the database and images from Android backup is a two-file change. Encryption is required before real-customer rollout.
2. **Run the physical tablet checklist** in `STAGE1_PILOT_READINESS.md` §9 and the Stage 1C checklist. Add these two checks:
   - change a price on a second device, restart the tablet, wait about 15 s, and ring the item: the new price shows and the sale succeeds (A-3);
   - toggle airplane mode during a Khata payment: there is a single entry and the button is disabled until done (A-4).
3. **Accept or schedule** IMG-1/2 and PRN-1 in writing (the documented workarounds).
4. **Commit this work in reviewable pieces.** Stage 1B, the keyboard-focus work, Stage 2 l10n and this audit are all uncommitted on one branch. Commit them separately. Before pushing, apply B-11 (HTTP fixture stock) so CI's R1 job stays green. Then raise the CI floor (B-9) and let CI run the HTTP, raw SQL and pgTAP layers that were not run here.
5. **Confirm no pilot tablet was first installed at Drift v7 or v8.** If one was, A-9 repairs it on next launch; no data action is needed.

## 8. What can wait until usage grows

- B-1 index: ship it with the next server migration; it is mandatory before about 50 active shops (see §9).
- B-2 limits: before any shop approaches 5,000 SKUs (a typical kiryana has 500–3,000).
- B-3 local performance (R5): before shops reach about 6 months of busy history.
- B-4 periodic pull: before multi-tablet shops.
- B-5, B-6, B-7, B-8, B-10: housekeeping or product decisions.

---

## 9. Scaling plan

### Targets and assumptions

- **Documented target:** the forensic audit's 5,000-shop release gate and workload model, used here unchanged (**Estimate**):

  | | Normal | Busy | Stress |
  | --- | --- | --- | --- |
  | Devices × sales/shop/day | 2 × 300 | 3 × 700 | 5 × 1,500 |
  | Sales/day | 1.5 M | 3.5 M | 7.5 M |
  | Rows/day | 13.7 M | 38.9 M | 98.3 M |
  | Peak checkout RPC/s | ~125 | ~290 | ~625 |

- **Immediate reality:** 1 shop (Ali_shop), 1 Galaxy Tab A9+, plain SQLite, a hosted Supabase project.
- **Measured by others (not re-measured here):**
  - checkout RPC ≈ 7.7 ms single-client and ≈ 240–270 TPS on a 4 vCPU local Postgres, database only;
  - 1-year busy-shop device: catalog reload 9.6 s, startup 10.1 s (v10 DDL).
- Nothing in this section was load-tested in this audit.

### Prioritised plan

| Pri | Bottleneck (code path) | Why it breaks | How to measure | Change | When |
| --- | --- | --- | --- | --- | --- |
| 1 | B-1 `customer_ledger_entries` scan per sale upload | O(total ledger rows) per checkout RPC; degrades for every tenant at once | Seed 10M ledger rows; `EXPLAIN ANALYZE` the sale RPC; k6 at 125 RPC/s | Partial index on `sale_id` (SQL above) | Next migration; before ~50 shops |
| 2 | Device: catalog reload and stock sums (B-3, A-7 partly fixed) | Linear in movement history; runs after each checkout | 1-year busy fixture with stopwatch budgets in an opt-in test (like `stress_performance_test.dart`) | Stock projection table, local indexes (Drift v14), outbox pruning | Before shops pass ~6 months of busy history |
| 3 | Connections: PostgREST pool vs. tablets syncing in bursts | Each tablet sends its RPCs serially (10 per pass), but morning reconnect storms after a power or Internet outage can queue thousands of RPCs | k6: 1,000 simulated devices draining 50-op backlogs; watch the pool wait time and p95 | Supavisor transaction pooling; client-side jitter on the 2-minute timer; batched push RPC (R6) | Before ~500 shops |
| 4 | Storage growth: `sale_items`, `inventory_movements`, `sale_payments`, `audit_logs` (~5 B rows/yr in the Normal profile) | Index bloat, vacuum and backup time; Supabase disk tier cost | Monthly `pg_total_relation_size` trend per table | Time partitioning by month on the append-only tables; retention for `audit_logs`; snapshot initial sync for new devices | Before ~1,000 shops |
| 5 | Pull: owner screens and `device_pull` page from `(shop_id, server_seq, id)` (indexed, R1.4) | Fine per page; initial sync of an old shop re-pulls all history | Time a fresh-device pull for a 1-year shop | Snapshot plus bounded history for new devices (R6) | When shops older than ~6 months add a tablet |
| 6 | Edge function `issue-entitlement` | One call per owner sign-in or cashier hand-off; Supabase invocation quotas | Invocation count per shop per day | Fine; cache, and skip the cashier-mode call (B-5) | Low priority |
| 7 | Images (IMG-1 design) | Storage egress per device per image | Bucket egress per day after Storage ships | Content-hashed keys plus a device disk cache, as designed | With IMG-1 |
| 8 | Sign-up abuse (T25: open sign-up, unlimited trial shops) | Cost and row growth from junk tenants | Shops created per day | Captcha / invite or phone verification; trial limits | Before public launch |

Operating-cost note (**Estimate**): at the Normal profile the database
outgrows small Supabase tiers within months (~1.3 TB/year). Partitioning plus
retention (row 4) is the cost lever, not compute.
