# R1 recovery test harness

Everything here lives outside `test/`, so the normal `flutter test` run (the
R0 baseline: at least 95 passed, at most 1 skipped) is unaffected. Each layer is
invoked explicitly.

| Directory | Tag | Green or red | Needs |
| --- | --- | --- | --- |
| `guard/` | `r1-guard` | green | nothing |
| `tz/` | `r1-tz` | green | `TZ` + `EXPECTED_TZ_OFFSET_MINUTES` |
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

## Expected-red suite

`red/` contains reproductions of accepted findings F-1, F-2, O-2 (A and B),
F-3/O-4, O-6, T-1, T-1b and the HTTP contract skeletons for R1.3–R1.5. Each
asserts the correct invariant and therefore fails on the current code.
`red/EXPECTED_RED.txt` lists every test by exact name.
`.github/scripts/expect_red.py` passes only if every listed test fails for an
assertion (a widget test's `TestFailure` counts; any other exception, timeout,
skip, missing or extra test fails the gate), and it fails when a listed test
turns green — the fixing substage must move that test into the green suite and
remove its manifest line in the same change.

T-1 depends on the device time zone, so the red suite always runs with
`TZ=Asia/Karachi`; under UTC it would pass, which is how CI hid it before.

## Running locally

```bash
bash tool/r1_integration/run_local.sh
```

The script brings up the disposable HTTP stack (`tool/r1_integration/local_http_stack.sh`:
GoTrue, PostgREST and Kong from the images of the running local dev stack,
against scratch database `r1_http`, published on `127.0.0.1:54421`), runs every
layer, applies the red gate and always tears the stack down.

CI (`r1-integration` job) runs the same layers against a fresh `supabase start`
stack instead of the local mini-stack.
