# R1 recovery test harness

Everything here lives outside `test/`, so the normal `flutter test` run (the
R0 baseline: at least 95 passed, at most 1 skipped) is unaffected. Each layer is
invoked explicitly.

| Directory | Tag | Green or red | Needs |
| --- | --- | --- | --- |
| `guard/` | `r1-guard` | green | nothing |
| `tz/` | `r1-tz` | green | `TZ` + `EXPECTED_TZ_OFFSET_MINUTES` |
| `green/` | `r1-green` | green (fixed findings) | nothing |
| `direct_db/` | `r1-direct-db` | green | Docker + `R1_SERVER=true` |
| `http/` | `r1-http` | green | local HTTP stack + `R1_HTTP_URL` / `R1_HTTP_ANON_KEY` |
| `red/` | `recovery-red` | **expected red** | all of the above, `TZ=Asia/Karachi` |
| `server_seq_prototype/` | — | design validation script | Docker |

## Layers

- **Direct-DB (fast):** `support/direct_db_server.dart` creates a scratch
  database `r1_direct_<file>` inside the local Supabase Postgres container, applies
  all migrations from zero, runs RPCs and pull queries as `authenticated` with a
  JWT claim, and drops the database in `tearDownAll`. The dev database is never
  written.
- **HTTP (real path):** `support/http_stack.dart` drives Kong → GoTrue /
  PostgREST through the app's own `SupabaseSaleUploadGateway`,
  `SupabaseReferencePullGateway`, `ReferencePullService` and `SyncWorker`. Setup
  uses public APIs only (sign-up + owner RPCs); there is no service-role key.
  Each test signs up its own owner and shop.
- **Devices:** `support/sim_device.dart` gives each simulated device its own
  file-backed Drift database (restart = close + reopen), its own clock skew and a
  network mode (`online`, `offline`, `dropResponse`).
- **Guard:** `support/local_target_guard.dart` refuses any target that is not
  `localhost` or a loopback IP literal before a client exists, and blocks any
  non-loopback socket through `HttpOverrides`. `guard/` proves both.

## Green regression suite (fixed findings)

`green/` holds the tests of findings a substage has fixed, kept with their
original names and assertions, plus that substage's contract tests. R1.1
(checkout durability + zero total) moved the three F-1 tests here and added
the checkout contract (commit-then-sync failure/hang, same/different content
under one checkout id, rapid double tap, restart after commit, zero-total,
rollback before commit) and its review corrections (Split at Rs 0, receipt
read back from the committed sale, customer-payment sync semantics, sales
findable in Bills after any restart delay, canonical replay audit).
R1.2 (T-1 timestamps) added `green/t1_timestamp_local_test.dart`,
`direct_db/t1_timestamp_test.dart` and `http/timestamp_http_test.dart`; these
three run under `TZ=UTC`, `Asia/Karachi` and `EST5` (UTC−05:00) with fixed
expected instants, and PostgreSQL renders the stored instant itself.
R1.3 (F-2 void convergence, void contract v2) added `green/void_local_test.dart`,
`direct_db/void_convergence_test.dart`, `direct_db/void_upgrade_test.dart`
(upgrade from the 18-migration R1.2 schema) and
`http/void_convergence_http_test.dart`; the void-window, restart and F-2 tests
also run in the three-zone matrix.
R1.4 (server-owned sync order, Drift v11) added `direct_db/sync_order_test.dart`
(counter prefix, identical and microsecond timestamps, pagination, restart,
repeated page, isolation, every pulled entity), `direct_db/ten_shop_sim_test.dart`
(10 shops x 2 devices), `direct_db/sync_order_upgrade_test.dart` (R1.3 -> R1.4
schema), `green/drift_v11_upgrade_test.dart` (Drift v10 -> v11 and fresh v11) and
`http/sync_order_http_test.dart`; O-2 and T-1b moved to green.
The green suite runs the production committer and background
sync runner on local Drift databases only (`support/pos_fixture.dart`).
`support/legacy_zero_payment.dart` crafts the pre-R1.1 Rs 0 payment-row
aggregate that R1.1 no longer creates but the server must keep rejecting.

## Expected-red suite

`red/` contains reproductions of accepted findings F-3/O-4 and O-6 and the
HTTP contract skeletons for R1.5 (F-1, T-1, F-2 with the v2 void contract, and
O-2, T-1b with server_seq were fixed by R1.1–R1.4; their tests moved to the
green layers). Each
asserts the correct invariant and therefore fails on the current code.
`red/EXPECTED_RED.txt` lists every test by exact name.
`.github/scripts/expect_red.py` passes only if every listed test fails for an
assertion (a widget test's `TestFailure` counts; any other exception, timeout,
skip, missing or extra test fails the gate), and it fails when a listed test
turns green — the fixing substage must move that test into the green suite and
remove its manifest line in the same change.

Time-zone dependent tests run under explicit `TZ` values and `tz/` proves each
zone took effect (UTC, Asia/Karachi, EST5): under UTC alone T-1 passed, which
is how CI hid it before R1.0. The red suite runs with `TZ=Asia/Karachi`.

## Running locally

```bash
bash tool/r1_integration/run_local.sh
```

The script brings up the disposable HTTP stack (`tool/r1_integration/local_http_stack.sh`:
GoTrue, PostgREST and Kong from the images of the running local dev stack,
against scratch database `r1_http`, published on `127.0.0.1:54421`, or `R1_HTTP_PORT` when Windows reserves
that port), runs every
layer, applies the red gate and always tears the stack down.

CI (`r1-integration` job) runs the same layers against a fresh `supabase start`
stack instead of the local mini-stack.
