// Device identity across APK updates and reinstalls, and the pending /
// replacement path. The server enforces the slot rule (migration
// 202610140001, proven by supabase/tests_raw/platform_admin_licensing_security.sql
// and tool/edge_functions); these tests pin the client side of it.
import 'package:dukaan_pro/app/device_approval_notice.dart';
import 'package:dukaan_pro/core/device/app_device_id.dart';
import 'package:dukaan_pro/core/device/device_code.dart';
import 'package:dukaan_pro/core/device/preferences_device_id_store.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/features/shop/device_registration_gateway.dart';
import 'package:dukaan_pro/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The preferences key every released build has used. Changing it (for
/// example per app version) would hand every updated tablet a new identity,
/// i.e. a new pending registration: exactly the duplicate this guards against.
const _releasedKey = 'dukaan_pro.app_device_id.v1';
const _installedId = '0192a3b4-c5d6-7e8f-9a0b-1c2d3e4f5a6b';

final class _CountingIds implements IdGenerator {
  _CountingIds(this.value);
  final String value;
  int calls = 0;
  @override
  String next() {
    calls++;
    return value;
  }
}

AppDeviceIdProvider _provider(IdGenerator ids) =>
    AppDeviceIdProvider(PreferencesDeviceIdStore(), ids);

void main() {
  group('device identity', () {
    test('in-place APK update keeps the installed identity', () async {
      // Android keeps the app's SharedPreferences on an update signed by the
      // same key (or a rotated key with lineage, docs/release-signing.md).
      SharedPreferences.setMockInitialValues({_releasedKey: _installedId});
      final newVersion = _CountingIds('should-not-be-used');
      expect(await _provider(newVersion).getOrCreate(), _installedId);
      // Every later launch of the new version: still the same, never minted.
      expect(await _provider(newVersion).getOrCreate(), _installedId);
      expect(newVersion.calls, 0);
    });

    test(
      'uninstall/reinstall or cleared data mints one new identity',
      () async {
        // Reinstall: Android deleted the preferences (and backup excludes them,
        // so a restore never clones another device's identity).
        SharedPreferences.setMockInitialValues({});
        final ids = _CountingIds('0192ffff-0000-7000-8000-000000000001');
        final first = await _provider(ids).getOrCreate();
        expect(first, isNot(_installedId));
        expect(await _provider(ids).getOrCreate(), first);
        expect(ids.calls, 1);
        expect(
          (await SharedPreferences.getInstance()).getString(_releasedKey),
          first,
        );
      },
    );
  });

  group('pending registration', () {
    test('server statuses map to the device page states', () {
      const pending = RegisteredDevice(
        id: 'd',
        isActive: false,
        approvalStatus: 'pending',
      );
      expect(pending.awaitingApproval, isTrue);
      expect(pending.isActive, isFalse);
      // A pre-licensing server reports no status: active means approved.
      expect(
        const RegisteredDevice(id: 'd', isActive: true).awaitingApproval,
        isFalse,
      );
    });

    test('device code is short, stable and derived from the server id', () {
      expect(deviceCode('d0a1b2c3-0000-4000-8000-000000000000'), 'D0A1B2C3');
      expect(deviceCode('d0a1b2c3-ffff-4000-8000-000000000000'), 'D0A1B2C3');
    });

    for (final locale in ['en', 'ur']) {
      testWidgets('pending notice explains replacement approval ($locale)', (
        tester,
      ) async {
        var checks = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: DeviceApprovalPendingNotice(
                deviceId: 'd0a1b2c3-0000-4000-8000-000000000000',
                onCheckAgain: () => checks++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(Locale(locale));
        expect(find.text(l10n.deviceApprovalPending), findsOneWidget);
        expect(find.text(l10n.deviceApprovalCode('D0A1B2C3')), findsOneWidget);
        if (locale == 'en') {
          expect(
            l10n.deviceApprovalPending,
            startsWith('Device replacement requires admin approval.'),
          );
        } else {
          expect(l10n.deviceApprovalPending, contains('ایڈمن کی منظوری'));
        }
        await tester.tap(find.text(l10n.deviceApprovalCheckAgain));
        expect(checks, 1);
      });
    }
  });
}
