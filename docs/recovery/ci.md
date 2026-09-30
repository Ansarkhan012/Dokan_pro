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

Flutter, the Supabase CLI and gitleaks are pinned to exact versions. GitHub
Actions are pinned to exact release tags; once a remote exists, convert them
to full commit SHAs (for example with a pinning tool) and verify.

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
