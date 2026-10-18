// Drift upgrade from every released snapshot (v7-v12) to the current schema
// matches a fresh install exactly: tables, columns and indexes. Before the
// audit fix (A-9, PROJECT_AUDIT.md) v7 and v8 failed: the v9 step created the
// return and void tables without their four indexes.
@Tags(['r1-green'])
library;

import 'package:drift_dev/api/migrations_native.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in GeneratedHelper.versions.where((v) => v < 13)) {
    test('v$from -> current matches a fresh install', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, db.schemaVersion);
    });
  }
}
