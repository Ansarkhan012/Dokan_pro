// Cashier/owner server boundary through the real Supabase HTTP path (Kong ->
// PostgREST/GoTrue) of a disposable LOCAL stack: cashier mode on the app's
// session-less device client, with no owner session anywhere in it.
@Tags(['r1-http'])
library;

import 'package:drift/native.dart';
import 'package:dukaan_pro/auth/device_credential.dart';
import 'package:dukaan_pro/auth/device_mode.dart';
import 'package:dukaan_pro/auth/supabase_cashier_auth_gateway.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/shop/device_cashier_directory.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/pull/supabase_reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/supabase_sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart' show posPullEntities;

const _pin = '4321';

void main() {
  late LocalHttpStack stack;
  final clients = <SupabaseClient>[];
  final databases = <AppDatabase>[];

  setUpAll(() async {
    if (r1HttpConfigured) stack = await LocalHttpStack.connect();
  });
  tearDown(() async {
    for (final db in databases) {
      await db.close();
    }
    databases.clear();
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });
  tearDownAll(() async {
    if (r1HttpConfigured) await stack.dispose();
  });

  const skip = r1HttpConfigured ? false : r1HttpSkipReason;

  /// A shop with one tablet registered under a known identifier, one cashier
  /// and that tablet's device credential, provisioned by the owner.
  Future<_Tablet> provisionedTablet() async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final rpc = shop.owner.client.rpc;
    final identifier = const Uuid().v4();
    final deviceId =
        ((await rpc('register_shop_device', params: {
                      'p_shop_id': shop.shopId,
                      'p_device_name': 'Counter tablet',
                      'p_device_type': 'androidTablet',
                      'p_device_identifier': identifier,
                    })
                    as List)
                .single
            as Map)['device_id']
        as String;
    final cashierId =
        await rpc('create_cashier', params: {
              'p_shop_id': shop.shopId,
              'p_display_name': 'Ahmed',
              'p_login_code': 'ahmed',
              'p_pin': _pin,
            })
            as String;
    final secret = await SupabaseDeviceCredentialIssuer(
      shop.owner.client,
    ).issue(shopId: shop.shopId, deviceId: deviceId);
    final credential = DeviceCredential(
      shopId: shop.shopId,
      shopName: 'R1 shop',
      deviceId: deviceId,
      deviceIdentifier: identifier,
      secret: secret,
    );
    final db = AppDatabase(NativeDatabase.memory());
    databases.add(db);
    return _Tablet(shop, deviceId, identifier, cashierId, credential, db);
  }

  SupabaseClient deviceClient(DeviceCredential credential) {
    final client = deviceSupabaseClient(
      url: stack.url.toString(),
      anonKey: stack.anonKey,
      credential: credential,
    );
    clients.add(client);
    return client;
  }

  Future<void> pullAll(_Tablet tablet, SupabaseClient client) async {
    final service = ReferencePullService(
      tablet.db,
      DeviceReferencePullGateway(client),
      shopId: tablet.shop.shopId,
    );
    for (final entity in posPullEntities) {
      await service.pull(entity);
    }
  }

  Future<CreatedSale> sell(_Tablet tablet, {DateTime Function()? clock}) =>
      LocalSaleService(tablet.db, const UuidV7Generator(), clock: clock)
          .createSale(
            SaleDraft(
              shopId: tablet.shop.shopId,
              cashierId: tablet.cashierId,
              deviceId: tablet.deviceId,
              lines: [SaleLineDraft(productId: tablet.shop.productId, quantity: 1000)],
              payments: const [
                SalePaymentDraft(
                  method: PaymentMethod.cash,
                  amountMinor: ServerShop.salePrice,
                ),
              ],
            ),
          );

  Future<SyncWorkerResult> sync(
    _Tablet tablet,
    SupabaseClient client, {
    String? token,
  }) => SyncWorker(
    queue: SyncQueueRepository(tablet.db, shopId: tablet.shop.shopId),
    gateway: SupabaseSaleUploadGateway(client),
    workerId: 'device-boundary-${const Uuid().v4()}',
    cashierToken: () async => token,
  ).runOnce();

  Future<Map<String, dynamic>?> serverSale(_Tablet tablet, String saleId) async =>
      await tablet.shop.owner.client
          .from('sales')
          .select('id,cashier_id,device_id')
          .eq('id', saleId)
          .maybeSingle();

  test('cashier mode bills, logs in and syncs on the device credential alone', () async {
    final tablet = await provisionedTablet();
    final client = deviceClient(tablet.credential);
    expect(client.auth.currentSession, isNull, reason: 'no owner session');

    // Read path: the POS reference data arrives through device_pull.
    await pullAll(tablet, client);
    final products = await tablet.db.select(tablet.db.shopProducts).get();
    expect(products.map((p) => p.id), contains(tablet.shop.productId));
    expect(
      (await DeviceCashierDirectory(client).cashiers(shopId: tablet.shop.shopId))
          .map((c) => c.displayName),
      ['Ahmed'],
    );

    // Online login and a sale under the live cashier session.
    final session = await SupabaseCashierAuthGateway(client).authenticate(
      shopId: tablet.shop.shopId,
      deviceIdentifier: tablet.identifier,
      cashierId: tablet.cashierId,
      pin: _pin,
    );
    final live = await sell(tablet);
    expect((await sync(tablet, client, token: session.token)).synced, 1);
    expect(await serverSale(tablet, live.saleId), {
      'id': live.saleId,
      'cashier_id': tablet.cashierId,
      'device_id': tablet.deviceId,
    });

    // Billed offline during the session; the cashier logs out before the
    // upload: the historical session proof syncs it without any token.
    final offline = await sell(tablet);
    await SupabaseCashierAuthGateway(client).revoke(session);
    expect((await sync(tablet, client)).synced, 1);
    expect((await serverSale(tablet, offline.saleId))?['cashier_id'], tablet.cashierId);

    // A sale dated after the logout cannot use that proof.
    final late = await sell(
      tablet,
      clock: () => DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    expect((await sync(tablet, client)).synced, 0);
    final operation = (await tablet.db.select(tablet.db.syncOperations).get())
        .singleWhere((op) => op.entityId == late.saleId);
    expect(operation.status, SyncStatus.blockedAuth);
    expect(await serverSale(tablet, late.saleId), isNull);

    // The pulled sales converge without duplicates.
    await pullAll(tablet, client);
    final sales = await tablet.db.select(tablet.db.sales).get();
    expect(sales.where((s) => s.id == live.saleId), hasLength(1));
    expect(sales.where((s) => s.id == offline.saleId), hasLength(1));
  }, skip: skip);

  test('the device credential reaches no owner operation', () async {
    final tablet = await provisionedTablet();
    final client = deviceClient(tablet.credential);
    final shopId = tablet.shop.shopId;
    final refused = <String, Future<Object?> Function()>{
      'owner report': () => client.rpc('owner_report_summary', params: {
        'p_shop_id': shopId,
        'p_start': DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String(),
        'p_end': DateTime.now().toUtc().toIso8601String(),
      }),
      'create cashier': () => client.rpc('create_cashier', params: {
        'p_shop_id': shopId, 'p_display_name': 'Rogue', 'p_login_code': 'rogue', 'p_pin': '9999',
      }),
      'deactivate cashier': () => client.rpc('set_cashier_active', params: {
        'p_shop_id': shopId, 'p_cashier_id': tablet.cashierId, 'p_is_active': false,
      }),
      'product price': () => client
          .from('shop_products')
          .update({'sale_price': 1})
          .eq('id', tablet.shop.productId)
          .select(),
      'credit limit': () => client
          .from('customers')
          .update({'credit_limit': null})
          .eq('id', tablet.shop.customerId)
          .select(),
      'inventory adjustment': () => client.rpc('sync_inventory_adjustment', params: {'p_payload': {}}),
      'purchase': () => client.rpc('sync_purchase_transaction', params: {'p_payload': {}}),
      'expense': () => client.rpc('sync_expense', params: {'p_payload': {}}),
      'register device': () => client.rpc('register_shop_device', params: {
        'p_shop_id': shopId, 'p_device_name': 'X', 'p_device_type': 'androidTablet',
        'p_device_identifier': const Uuid().v4(),
      }),
      'device administration': () => client
          .from('devices')
          .update({'is_active': false})
          .eq('id', tablet.deviceId)
          .select(),
      'credential provisioning': () => client.rpc('issue_device_credential', params: {
        'p_shop_id': shopId, 'p_device_id': tablet.deviceId,
      }),
      'void': () => client.rpc('sync_sale_void', params: {'p_payload': {}}),
      'return': () => client.rpc('sync_sale_return', params: {'p_payload': {}}),
      'settings': () => client.rpc('update_shop_settings', params: {
        'p_shop_id': shopId, 'p_name': 'X', 'p_phone': '', 'p_address': '',
        'p_allow_negative_stock': true, 'p_default_low_stock_level': 0,
        'p_receipt_footer': '', 'p_receipt_paper_width': '80mm',
        'p_receipt_show_phone': true, 'p_receipt_show_address': true,
        'p_notifications_enabled': false,
      }),
      'subscription claims': () => client.rpc('entitlement_claims', params: {
        'p_shop_id': shopId, 'p_device_id': tablet.deviceId,
      }),
      'direct sales read': () => client.from('sales').select('id'),
    };
    for (final MapEntry(key: name, value: call) in refused.entries) {
      Object? result;
      Object? error;
      try {
        result = await call();
      } catch (e) {
        error = e;
      }
      // Refused for lack of privilege: never "not found" or a validation error.
      expect(
        error is PostgrestException ? error.code : error,
        '42501',
        reason: '$name returned ${result ?? error}',
      );
    }
    // Nothing changed on the server.
    final product = await tablet.shop.owner.client
        .from('shop_products')
        .select('sale_price')
        .eq('id', tablet.shop.productId)
        .single();
    expect(product['sale_price'], ServerShop.salePrice);
  }, skip: skip);

  test('rotation and deactivation fail closed', () async {
    final tablet = await provisionedTablet();
    final old = deviceClient(tablet.credential);
    await old.rpc('device_pull', params: {'p_entity': 'shops'});

    final rotated = await SupabaseDeviceCredentialIssuer(
      tablet.shop.owner.client,
    ).issue(shopId: tablet.shop.shopId, deviceId: tablet.deviceId);
    await expectLater(
      old.rpc('device_pull', params: {'p_entity': 'shops'}),
      throwsA(isA<PostgrestException>()),
    );
    final current = deviceClient(
      DeviceCredential(
        shopId: tablet.shop.shopId,
        shopName: 'R1 shop',
        deviceId: tablet.deviceId,
        deviceIdentifier: tablet.identifier,
        secret: rotated,
      ),
    );
    expect(await current.rpc('device_pull', params: {'p_entity': 'shops'}), hasLength(1));

    await tablet.shop.owner.client
        .from('devices')
        .update({'is_active': false})
        .eq('id', tablet.deviceId);
    await expectLater(
      current.rpc('device_pull', params: {'p_entity': 'shops'}),
      throwsA(isA<PostgrestException>()),
    );
  }, skip: skip);

  test('removing the owner session leaves no owner authority', () async {
    final owner = await stack.signUpOwner();
    final shop = await ServerShop.create(owner);
    final storage = _MemoryLocalStorage()..persisted = 'session-json';
    final authority = SupabaseOwnerAuthority(owner.client, storage);
    expect(authority.isSignedIn, isTrue);
    expect(await authority.isGone(), isFalse);

    await authority.removeLocalSession();

    expect(await authority.isGone(), isTrue);
    expect(storage.persisted, isNull);
    await expectLater(
      owner.client.rpc('create_cashier', params: {
        'p_shop_id': shop.shopId, 'p_display_name': 'Rogue', 'p_login_code': 'rogue', 'p_pin': '9999',
      }),
      throwsA(isA<PostgrestException>()),
    );
  }, skip: skip);
}

final class _Tablet {
  _Tablet(this.shop, this.deviceId, this.identifier, this.cashierId, this.credential, this.db);
  final ServerShop shop;
  final String deviceId;
  final String identifier;
  final String cashierId;
  final DeviceCredential credential;
  final AppDatabase db;
}

final class _MemoryLocalStorage extends LocalStorage {
  String? persisted;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => persisted != null;
  @override
  Future<String?> accessToken() async => persisted;
  @override
  Future<void> removePersistedSession() async => persisted = null;
  @override
  Future<void> persistSession(String persistSessionString) async =>
      persisted = persistSessionString;
}
