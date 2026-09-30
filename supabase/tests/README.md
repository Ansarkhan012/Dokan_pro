# pgTAP database tests

Only TAP-emitting pgTAP suites belong in this directory because
`npx supabase@2.113.0 test db` runs every SQL file found here through
`pg_prove`.

Transaction-scoped, exception-driven integration and security checks live in
`../tests_raw`. Run them after a local database reset with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_raw_sql_tests.ps1
```

