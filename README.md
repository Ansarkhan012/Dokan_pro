# Dukaan Pro

Phase 0 architecture and offline-first local data foundation for a multi-tenant POS SaaS. See [architecture](docs/architecture.md), [offline sync](docs/offline-sync.md), and [database](docs/database.md).

Run verification with `flutter analyze` and `flutter test`.

**Recovery status:** the code at tag `pre-recovery-audit-baseline` has known
pilot-blocking defects recorded in the
[forensic audit and recovery roadmap](docs/recovery/forensic-audit-2026-09-30.md).
Read it before changing financial, sync, auth or security behaviour. CI and recovery status are
described in [docs/recovery/ci.md](docs/recovery/ci.md) and
[docs/recovery/status.md](docs/recovery/status.md).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
