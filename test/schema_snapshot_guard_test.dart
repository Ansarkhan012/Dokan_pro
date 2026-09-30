import 'dart:io';

import 'package:dukaan_pro/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'current Drift version has an authentic committed schema snapshot',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final version = db.schemaVersion;
      final snapshot = File('drift_schemas/drift_schema_v$version.json');
      expect(
        snapshot.existsSync(),
        isTrue,
        reason:
            'Every schema bump from v7 onward must commit its drift_dev snapshot.',
      );
      expect(await snapshot.readAsString(), contains('"entities"'));
      final generated = File('test/generated_migrations/schema_v$version.dart');
      expect(generated.existsSync(), isTrue);
      expect(
        await generated.readAsString(),
        contains('schemaVersion => $version'),
      );
    },
  );
}
