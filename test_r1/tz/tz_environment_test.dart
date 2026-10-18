// Proves the time-zone matrix actually changed the process time zone.
// Run with TZ=<zone> and --dart-define=EXPECTED_TZ_OFFSET_MINUTES=<minutes>;
// a silently ignored TZ makes this test fail, so a UTC-only run can never be
// mistaken for a Karachi run again (T-1 was hidden that way).
@Tags(['r1-tz'])
library;

import 'package:flutter_test/flutter_test.dart';

const _expected = int.fromEnvironment('EXPECTED_TZ_OFFSET_MINUTES', defaultValue: -99999);

void main() {
  test(
    'process time zone offset equals the matrix entry',
    () {
      // Pakistan and UTC have no DST, so every instant must give the same offset.
      final instants = [
        DateTime.utc(2026, 1, 15, 12),
        DateTime.utc(2026, 7, 15, 12),
        DateTime.utc(2026, 9, 30, 4, 59, 26),
      ];
      for (final instant in instants) {
        final local = instant.toLocal();
        // ignore: avoid_print
        print('TZ_EVIDENCE ${instant.toIso8601String()} -> local ${local.toIso8601String()} '
            'offset=${local.timeZoneOffset} zone=${local.timeZoneName}');
        expect(local.timeZoneOffset.inMinutes, _expected);
        expect(local.hour, (instant.hour + _expected ~/ 60) % 24);
      }
    },
    skip: _expected == -99999
        ? 'set --dart-define=EXPECTED_TZ_OFFSET_MINUTES and TZ for the matrix run'
        : false,
  );
}
