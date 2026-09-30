# Recovery status

| Phase | Status |
| --- | --- |
| R0 Baseline safety | **APPROVED** (2026-09-30) |
| R1 Stop data corruption | **NOT STARTED** |
| R2–R8 | Not started |

## R0 record

- Remote: `https://github.com/Ansarkhan012/Dokan_pro` (branch `main`)
- Baseline tag: `pre-recovery-audit-baseline` → commit
  `c35bffac213f246c29612499bcf4537e507583a9` (exact audited state)
- CI-verified commit: `abb3ad2` — GitHub Actions run `36669943199`, all jobs
  green. The status-only commit that adds this file is verified by its own run
  (recorded in the R0 completion report).
- Application behaviour: unchanged since the baseline tag. R0 commits touch
  only `.gitignore`, `.github/`, `.gitleaks.toml`, `README.md` and
  `docs/recovery/`.

## Baseline test counts (asserted and published by CI)

| Suite | Count |
| --- | --- |
| Toolchain | Flutter 3.44.1 / Dart 3.12.1; Supabase CLI 2.113.0 |
| `flutter analyze` | 0 issues |
| `flutter test` | 95 passed, 1 skipped, 0 failed |
| Stress test (opt-in) | 1 passed |
| Migrations on a fresh stack | 18/18 |
| Raw SQL | 10/10 files |
| pgTAP | 40 tests in 4 files |
| gitleaks v8.21.2 (full history) | no leaks |

## CI run history during R0 finalisation

| Run | Commit | Result | Note |
| --- | --- | --- | --- |
| 36668986201 | `e9745c3` | success | First push; SHA-pinned actions |
| 36669451963 | `eb4cd30` | success | Counts asserted and published |
| 36669684102 | `77c7768` | failure | `supabase start` exited 1 after the CLI version check passed; the same command passed before and after. Logs need sign-in, so the cause is unconfirmed (treated as a transient stack start failure). |
| 36669943199 | `abb3ad2` | success | Start failures now surfaced as annotations |

The audit findings in `forensic-audit-2026-09-30.md` remain **unfixed**.
