import 'package:dukaan_pro/app/cashier_login_panel.dart';
import 'package:dukaan_pro/features/shop/cashier_admin_gateway.dart';
import 'package:dukaan_pro/features/shop/device_cashier_directory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  // Never used for a request: the directory is faked and no login is tapped.
  final client = SupabaseClient('http://127.0.0.1:1', 'test-anon-key');
  tearDownAll(client.dispose);

  Future<void> pumpPanel(
    WidgetTester tester, {
    required bool allowManagement,
    List<CashierMetadata> cashiers = const [
      CashierMetadata(id: 'c1', displayName: 'Ahmed', isActive: true),
    ],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashierLoginPanel(
            key: UniqueKey(),
            client: client,
            shopId: 'shop-a',
            shopName: 'Shop A',
            deviceIdentifier: 'identifier-a',
            allowManagement: allowManagement,
            directory: _FakeDirectory(cashiers),
            onAuthenticated: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the device lobby never offers cashier management', (tester) async {
    await pumpPanel(tester, allowManagement: false);
    expect(find.text('Start Shift / Login'), findsOneWidget);
    expect(find.text('Manage cashiers'), findsNothing);

    await pumpPanel(tester, allowManagement: false, cashiers: const []);
    expect(find.text('Create first cashier'), findsNothing);
    expect(find.text('Manage cashiers'), findsNothing);
    expect(find.textContaining('Ask the owner'), findsOneWidget);
  });

  testWidgets('a verified owner can manage cashiers from the hub', (tester) async {
    await pumpPanel(tester, allowManagement: true);
    expect(find.text('Manage cashiers'), findsOneWidget);
  });

  test('the device directory cannot administer cashiers', () {
    final directory = DeviceCashierDirectory(client);
    expect(
      () => directory.createCashier(shopId: 's', displayName: 'X', pin: '1234'),
      throwsStateError,
    );
    expect(
      () => directory.setActive(shopId: 's', cashierId: 'c', isActive: false),
      throwsStateError,
    );
  });
}

final class _FakeDirectory implements CashierAdminGateway {
  _FakeDirectory(this.rows);
  final List<CashierMetadata> rows;
  @override
  Future<List<CashierMetadata>> cashiers({required String shopId}) async => rows;
  @override
  Future<String> createCashier({
    required String shopId,
    required String displayName,
    required String pin,
  }) => throw UnimplementedError();
  @override
  Future<void> setActive({
    required String shopId,
    required String cashierId,
    required bool isActive,
  }) => throw UnimplementedError();
}
