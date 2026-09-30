# Raw SQL verification

These files are fail-fast integration and security scripts. They deliberately
use PostgreSQL roles, expected-error blocks, and transaction rollback rather
than TAP output. They are excluded from `supabase test db` and executed by
`scripts/run_raw_sql_tests.ps1` through local Docker PostgreSQL with
`psql -v ON_ERROR_STOP=1`.

The runner maintains an explicit ordered file list and returns non-zero on the
first SQL or assertion failure.
