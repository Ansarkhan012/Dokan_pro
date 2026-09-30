# Forensic audit baseline and recovery roadmap (2026-09-30)

This document preserves the outcome of the forensic production-readiness audit
of the `pre-recovery-audit-baseline` tag. It exists so that later work knows
why recovery phases R1–R8 exist. **Nothing listed here as a finding is fixed at
this baseline.** Older phase documents in `docs/` describe intended behaviour
and in several places claim properties that the audit disproved; where they
conflict with this document, this document records the verified state.

Evidence types used below:

- **Measured** – reproduced by executing code, SQL or a benchmark.
- **Code** – established by reading the exact source/migration lines.
- **Estimate** – derived from stated assumptions; not measured.

## Verdict

Salvageable; no rewrite. The accounting core (integer paisa, thousandth
quantities, append-only movements/ledgers, one local transaction per aggregate
plus outbox, idempotent fingerprinted server RPCs, tenant RLS with composite
`(id, shop_id)` foreign keys) is sound. The app is a late Phase-2 prototype
with pilot-blocking defects in identity, offline start, pull sync, checkout
durability and scale.

## Baseline test state (measured at the tag)

| Suite | Result |
| --- | --- |
| `flutter analyze` | 0 issues |
| `flutter test` | 95 passed, 1 skipped (opt-in stress) |
| Stress test (`--dart-define=RUN_STRESS=true`) | pass |
| Raw SQL (`scripts/run_raw_sql_tests.ps1`) | 10/10 files |
| pgTAP (`supabase/tests`) | 40/40 |
| Supabase migrations on a fresh database | 18/18 |

Toolchain: Flutter 3.44.1, Dart 3.12.1, PostgreSQL 17, Drift schema v10
(snapshots v7–v10).

## Blockers (not fixed)

### CRITICAL

| ID | Finding | Evidence |
| --- | --- | --- |
| S-1 | Cashier runs inside the owner's Supabase session; "End cashier session" opens every owner screen (void, returns, adjustments, settings) without re-authentication. The server cannot distinguish cashier from owner. | Code: `lib/app/auth_gate.dart` (`exitCashier`, owner menu) |
| S-2 | Owner refresh token persisted in plaintext SharedPreferences; a revoked/stolen tablet can still read shop data, register a new active device and re-activate itself. | Code + measured SQL attacks T32–T34 |
| O-1 | Offline cold start impossible in the normal setup: bootstrap and device lookup need the network; the cached-cashier resume path is unreachable while an owner is signed in. | Code: `supabase_shop_bootstrap_gateway.dart`, `cashier_resume_gate_native.dart` |
| O-2 | Pull cursors for immutable financial tables use client-supplied `created_at`; late (offline) or clock-skewed uploads are never pulled by other devices. | Code: `supabase_reference_pull_gateway.dart`; measured T17 (2019-dated sale accepted) |
| F-1 | Checkout awaits network sync after the local commit; cart clears only afterwards; post-commit errors show "Nothing was charged". A re-ring creates a duplicate financial sale. | Code: `pos_runtime_native.dart`, `pos_state.dart`, `pos_workspace.dart` |
| F-2 | Void compensation is double-counted on the voiding device: the server mints new UUIDs for movements/ledger refunds and pull inserts them beside the local rows (stock and Udhaar refunded twice). | Code + measured T20 |
| P-1 | Server pull queries scale with total platform rows: `sale_payments` pull is a sequential scan of all tenants; `sale_items` scans a whole index; movement pulls sort the shop's full history per page. | Measured EXPLAIN on 600k sales / 1.8M items |
| P-2 | Device database degrades with age: catalogue reload after every checkout 9.6 s, startup loads all queue rows (265k, 584 MB) 10.1 s, pending-sync watcher 3.9 s per queue write (1-year busy shop, desktop CPU). Synced queue rows are never pruned. | Measured with the exact v10 DDL |

### HIGH

| ID | Finding | Evidence |
| --- | --- | --- |
| S-3 | `anon`/`authenticated` hold TRUNCATE/TRIGGER/REFERENCES on 7 procurement/expense tables (default ACL never revoked after migration 6). Not reachable via PostgREST today; TRUNCATE bypasses RLS. | Measured (`SET ROLE anon; TRUNCATE` succeeded, rolled back) |
| S-4 | Local SQLite unencrypted; Android backup not disabled; no FLAG_SECURE. | Code |
| F-3 | Events valid offline are permanently rejected at sync (credit limit, overpayment, zero-amount payment line, void window) and retried forever; no dead-letter or UI. | Measured T19, T35 |
| O-3 | POS pulls only at startup; other counters' sales, stock and Khata changes are invisible until restart. | Code |
| O-4 | No transient/permanent error classification, dead-letter state or failure UI. | Code |
| K-1 | No version control or CI existed before R0. | Resolved in R0 |

MEDIUM/LOW items recorded in the audit: server trusts price/cost snapshots and
timestamps (T17, T18, T21); direct table writes bypass RPC validation/audit,
cross-tenant category FK (T14), duplicate barcodes (T15); cashier PIN brute
force; open sign-up with unlimited trial shops (T25); partial-return rounding
can over-refund by a paisa; refund tender not validated; slow backlog drain;
lease-race and multiple DB connections; dead code; missing MANAGER role.

Positive, measured: all 13 direct cross-tenant attacks were blocked; 320
concurrent identical sale submissions produced exactly one sale.

## Tests known to be missing

- Dart ↔ local Supabase integration tests for sync (all sync tests use fakes),
  including two-device sale/void/return/payment → pull convergence.
- Drift upgrade tests from each released snapshot (v7–v10) with financial data.
- Catalogue-driven privilege test (every table, every client role).
- Cashier-exit privilege boundary widget test.
- Offline cold-start test.
- Checkout hang/throw test asserting exactly one sale and a truthful message.
- Representative (1-year volume) local performance budgets.
- HTTP-level (PostgREST) load test.

## 5,000-shop workload model (estimates)

Assumptions: 14 trading hours; peak hour 15% of daily sales with 2× burst;
3/4/5 items per sale; 1.1 payments per sale; measured density ≈ 2.4 KB per
3-item sale aggregate including indexes.

| | Normal | Busy | Stress |
| --- | --- | --- | --- |
| Devices × sales/shop/day | 2 × 300 | 3 × 700 | 5 × 1,500 |
| Sales/day | 1.5 M | 3.5 M | 7.5 M |
| Rows/day | 13.7 M | 38.9 M | 98.3 M |
| Rows/year | 5.0 B | 14.2 B | 35.9 B |
| Storage/year | ~1.3 TB | ~3.8 TB | ~9.6 TB |
| Peak checkout RPC/s | ~125 | ~290 | ~625 |

Measured capacity: checkout RPC ≈ 7.7 ms single-client and ≈ 240–270 TPS on a
4 vCPU local Postgres (database only; no PostgREST/TLS).

## Recovery roadmap

| Phase | Goal | Scope |
| --- | --- | --- |
| R0 | Baseline safety | Git baseline + tag, strict `.gitignore`, CI, this document |
| R1 | Stop data corruption | F-1 checkout decoupling, F-2 void IDs + repair, O-2 server-sequence cursors, F-3/O-4 dead-letter and record-and-flag, payment contract, sync races; two-device integration suite |
| R2 | Identity and device security | S-1, S-2, O-1, S-4, PIN hardening: device credential, owner step-up, offline cashier switching, encrypted local DB |
| R3 | Database hardening | S-3 privileges + default ACLs, tenant-scoped FKs, unique barcode, price-override/price audit, `received_at`, rounding remainder, refund tender rules |
| R4 | Migration safety | Drift upgrade tests for every snapshot; pre-upgrade local backup |
| R5 | Local performance | Stock projection or covering index, incremental catalogue refresh, queue pruning, COUNT watchers, SQL search, single DB instance |
| R6 | Server scale | `(shop_id, server_seq)` indexes, snapshot initial sync, bounded history, batched push, partitioning, k6 load test |
| R7 | Launch features | Shifts/cash reconciliation, invoice numbers, printing, MANAGER role, discounts/override permissions, weighted items, purchase returns, Urdu, backup/export |
| R8 | UX polish | Cashier speed and safety |

Order of dependency: R0 → R1 → (R2 ∥ R3) → R4 → R5 → R6 → R7 → R8.

## 5,000-shop release gate

- [ ] Version control; CI green on a fresh ephemeral stack
- [ ] Cashier cannot reach owner functions without step-up; no owner refresh token on POS devices
- [ ] Revoked device fails all reads/RPCs on next contact
- [ ] Offline cold start reaches a working POS
- [ ] Checkout independent of network; hang/throw yields exactly one sale
- [ ] Void/return/payment converge across devices after sync and pull
- [ ] Server-assigned pull cursor; backdated/skewed uploads reach peers
- [ ] Dead-letter with owner resolution; no infinite retries
- [ ] Offline facts recorded and flagged, not silently rejected
- [ ] Client roles hold only whitelisted privileges (catalogue-driven test)
- [ ] Unique `(shop_id, barcode)`; tenant-scoped FKs; price-change audit
- [ ] Encrypted local DB; backups disabled; FLAG_SECURE on sensitive screens
- [ ] Drift upgrade tests for every released snapshot
- [ ] 1-year busy-shop device budget: checkout < 300 ms, startup < 3 s
- [ ] Synced-operation retention
- [ ] No sequential scan in any pull plan (EXPLAIN gate)
- [ ] Snapshot initial sync, bounded history, batched push
- [ ] PostgREST load test at Busy profile with measured results
- [ ] Partitioning/retention for sale_items, inventory_movements, sale_payments, audit_logs, sales
- [ ] Backup/PITR restore drill; per-shop export
- [ ] Shifts, invoice numbers, printing, MANAGER role, discount permissions, Urdu
