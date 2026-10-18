// SEC-1 (PROJECT_AUDIT.md): the local database and its SQLite companion files
// never leave the tablet in an Android backup or device transfer, on every
// supported Android version (minSdk 24: backup_rules.xml for 7-11,
// data_extraction_rules.xml for 12+). The manifest must point at both files.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res/xml';
const _excluded = [
  '<exclude domain="sharedpref" path="." />',
  '<exclude domain="file" path="dukaan_pro.sqlite" />',
  '<exclude domain="file" path="dukaan_pro.sqlite-journal" />',
  '<exclude domain="file" path="dukaan_pro.sqlite-wal" />',
  '<exclude domain="file" path="dukaan_pro.sqlite-shm" />',
];

String _section(String xml, String tag) {
  final start = xml.indexOf('<$tag>');
  final end = xml.indexOf('</$tag>');
  expect(start, isNonNegative, reason: '<$tag> missing');
  return xml.substring(start, end);
}

void main() {
  test('the database file name the rules exclude is the one the app opens', () {
    final source = File('lib/database/app_database.dart').readAsStringSync();
    expect(source, contains("'dukaan_pro.sqlite'"));
    expect(source, contains('getApplicationSupportDirectory()'));
  });

  test('Android 7-11 full backup excludes the database', () {
    final xml = File('$_res/backup_rules.xml').readAsStringSync();
    final rules = _section(xml, 'full-backup-content');
    for (final rule in _excluded) {
      expect(rules, contains(rule));
    }
  });

  test('Android 12+ cloud backup and device transfer exclude the database', () {
    final xml = File('$_res/data_extraction_rules.xml').readAsStringSync();
    for (final tag in ['cloud-backup', 'device-transfer']) {
      final rules = _section(xml, tag);
      for (final rule in _excluded) {
        expect(rules, contains(rule), reason: tag);
      }
    }
  });

  test('the manifest uses both rule files', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });
}
