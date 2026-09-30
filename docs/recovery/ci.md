# Continuous integration (recovery phase R0)

Workflow: `.github/workflows/ci.yml`. It reproduces the audited baseline and
must stay green before any recovery phase merges.

| Job | What it proves |
| --- | --- |
| `secret-scan` | No build output, local runtime state, database or signing material is tracked; gitleaks finds no secret in full history (`.gitleaks.toml` narrowly allowlists three reviewed non-secret literals). |
| `flutter` | Toolchain equals the audited Flutter 3.44.1 / Dart 3.12.1; `pubspec.lock` resolves unchanged (`--enforce-lockfile`); `flutter analyze`; `flutter test`; opt-in stress test. |
| `database` | A fresh, ephemeral local Supabase stack applies every migration and the seed from zero; migration-count check; raw SQL suites in the order listed in `scripts/run_raw_sql_tests.ps1`; pgTAP via `supabase test db`. |

## Safety rules

- No repository secrets are referenced. No step links to, pushes to, or
  deploys any hosted Supabase project. The stack's demo keys are ephemeral.
- Workflow permissions are `contents: read`.
- Local runtime secrets under `supabase/.temp/` are git-ignored and must never
  be committed.

## Pinning

Flutter, the Supabase CLI and gitleaks are pinned to exact versions. Every
GitHub Action is pinned to a full commit SHA. Each SHA was resolved on
2026-09-30 from two independent sources (`git ls-remote` of the tag and the
GitHub commits API); both agreed, and all three are lightweight tags.

| Action / tool | Version | Immutable reference |
| --- | --- | --- |
| `actions/checkout` | v4.2.2 | `11bd71901bbe5b1630ceea73d27597364c9af683` |
| `subosito/flutter-action` | v2.18.0 | `f2c4f6686ca8e8d6e6d0f28410eeef506ed66aff` |
| `supabase/setup-cli` | v1.5.0 | `d347ba47d3fb7eeeddbbc793bc8d4779caf773ea` |
| `ghcr.io/gitleaks/gitleaks` image | v8.21.2 | `sha256:0e99e8821643ea5b235718642b93bb32486af9c8162c8b8731f7cbdc951a7f46` |
| Supabase CLI (installed by setup-cli) | 2.113.0 | release `v2.113.0` |
| Flutter SDK | 3.44.1 (Dart 3.12.1) | tag `3.44.1` = `924134a44c189315be2148659913dda1671cbe99` |

Upgrading any row is a deliberate change: re-resolve and re-verify the SHA
or digest, and update this table in the same commit.

## Baseline floors and public evidence

CI asserts the audited baseline as floors (`BASELINE_MIN_*` in the workflow):
at least 95 Flutter tests passed with at most 1 skipped and none failed, the
stress test passed, at least 18 migrations applied (and equal to the file
count), at least 10 raw SQL files and 40 pgTAP tests passed. Exact counts are
emitted as `::notice` annotations, which are readable from the public
check-runs API without signing in to view logs. Raise a floor when tests are
added; never lower one to make CI pass.

## Known non-blocking notice

GitHub runners report that `actions/checkout` v4.2.2, `actions/cache` (used
inside flutter-action) and `supabase/setup-cli` v1.5.0 target Node.js 20 and
are run on Node.js 24. This is a deprecation notice, not a failure. Upgrading
these actions is a deliberate future change (re-resolve SHAs, update the
table above).

## Local equivalents

```powershell
flutter analyze
flutter test
flutter test test/stress_performance_test.dart --dart-define=RUN_STRESS=true
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_raw_sql_tests.ps1
```

The raw SQL runner targets the developer's running local stack and rolls every
test back. CI instead uses a fresh stack per run.

## Known limitation

At R0 no remote exists, so the workflow has been reviewed and its parts
reproduced locally, but it has not executed on GitHub.
