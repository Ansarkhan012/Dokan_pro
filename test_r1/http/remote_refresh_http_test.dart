// B-4 over the real HTTP path (PROJECT_AUDIT.md §0.12): a cashier tablet
// reading through its device credential (device_pull), exactly as the POS
// runtime does, with the runtime's RemoteRefresh guard.
//   1. A price the owner changes on another device reaches the tablet's
//      catalog on resume, on the same open database: no restart.
//   2. Offline, the refresh fails fast and changes nothing; the tablet keeps
//      selling from its cached catalog under the documented rules (cached
//      price, never oversell). When connectivity returns, the next tick pulls
//      the new price and later sales use it.
@Tags(['r1-http'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:dukaan_pro/auth/device_credential.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/features/pos/drift_pos_catalog.dart';
import 'package:dukaan_pro/features/pos/pos_state.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:dukaan_pro/sync/pull/remote_refresh.dart';
import 'package:dukaan_pro/sync/pull/supabase_reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/supabase_sale_upload_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/http_stack.dart';
import '../support/sim_device.dart' show posPullEntities;

const _newPrice = 20000; // Rs 200.00 (seeded Rs 180.00)

void main() {
  late LocalHttpStack stack;
  final clients = <SupabaseClient>[];
  final databases = <AppDatabase>[];
  const skip = r1HttpConfigured ? false : r1HttpSkipReason;

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

  /// A provisioned tablet: device, cashier, device credential and its own
  /// database, filled by a first pull (as at POS start).
  Future<_Tablet> tablet() async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final rpc = shop.owner.client.rpc;
    final identifier = shop.deviceAIdentifier; // the shop's tablet slot
    final deviceId = ((await rpc('register_shop_device', params: {
      'p_shop_id': shop.shopId,
      'p_device_name': 'Counter tablet',
      'p_device_type': 'androidTablet',
      'p_device_identifier': identifier,
    }) as List).single as Map)['device_id'] as String;
    final cashierId = await rpc('create_cashier', params: {
      'p_shop_id': shop.shopId,
      'p_display_name': 'Ahmed',
      'p_login_code': 'ahmed',
      'p_pin': '4826',
    }) as String;
    final secret = await SupabaseDeviceCredentialIssuer(shop.owner.client)
        .issue(shopId: shop.shopId, deviceId: deviceId);
    final client = deviceSupabaseClient(
      url: stack.url.toString(),
      anonKey: stack.anonKey,
      credential: DeviceCredential(
        shopId: shop.shopId,
        shopName: 'R1 shop',
        deviceId: deviceId,
        deviceIdentifier: identifier,
        secret: secret,
      ),
    );
    clients.add(client);
    final db = AppDatabase(NativeDatabase.memory());
    databases.add(db);
    final t = _Tablet(shop, deviceId, cashierId, db, _Switchable(DeviceReferencePullGateway(client)));
    expect(await t.pull(), isTrue, reason: 'first pull at POS start');
    return t;
  }

  Future<int> catalogPrice(_Tablet t) async =>
      (await DriftPosCatalog(t.db, shopId: t.shop.shopId).load())
          .products
          .singleWhere((p) => p.id == t.shop.productId)
          .salePriceMinor;

  Future<void> ownerChangesPrice(_Tablet t) => t.shop.owner.client
      .from('shop_products')
      .update({'sale_price': _newPrice})
      .eq('shop_id', t.shop.shopId)
      .eq('id', t.shop.productId);

  Future<CreatedSale> sell(_Tablet t, {required int quantity, required int paid}) =>
      LocalSaleService(t.db, const UuidV7Generator()).createSale(SaleDraft(
        shopId: t.shop.shopId,
        cashierId: t.cashierId,
        deviceId: t.deviceId,
        lines: [SaleLineDraft(productId: t.shop.productId, quantity: quantity)],
        payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: paid)],
      ));

  test('a price changed on another device reaches the open POS on resume, without a restart', () async {
    final t = await tablet();
    expect(await catalogPrice(t), ServerShop.salePrice);
    final cart = PosCart()
      ..add(PosProduct(
        id: t.shop.productId, name: 'Coke', salePriceMinor: ServerShop.salePrice,
        stockQuantity: ServerShop.openingStock, stockTrackingEnabled: true,
      ));

    await ownerChangesPrice(t);
    final remote = RemoteRefresh(pull: t.pull, minInterval: Duration.zero);
    expect(await remote.onResume(), isTrue, reason: 'resume pulls');
    expect(await catalogPrice(t), _newPrice, reason: 'same database, no restart');

    final changes = cart.refreshProducts(
      (await DriftPosCatalog(t.db, shopId: t.shop.shopId).load()).products,
    );
    expect(changes.single.oldPriceMinor, ServerShop.salePrice);
    expect(changes.single.newPriceMinor, _newPrice);
    expect(cart.subtotalMinor, _newPrice);
    final sale = await sell(t, quantity: 1000, paid: _newPrice);
    expect(sale.grandTotalMinor, _newPrice);
  }, skip: skip);

  test('offline: the refresh fails fast and the POS keeps selling from its cache', () async {
    final t = await tablet();
    await ownerChangesPrice(t);
    t.gateway.offline = true;
    final remote = RemoteRefresh(pull: t.pull, minInterval: Duration.zero);

    final watch = Stopwatch()..start();
    expect(await remote.onResume(), isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)), reason: 'stops at the first failure');
    expect(t.gateway.calls, 1, reason: 'one failed request, not one per entity');
    expect(remote.waitingForConnectivity, isTrue);
    expect(await catalogPrice(t), ServerShop.salePrice, reason: 'cached price kept');

    // Documented offline rules: the cached price is charged, and cached stock
    // still refuses an oversell.
    final offlineSale = await sell(t, quantity: 1000, paid: ServerShop.salePrice);
    expect(offlineSale.grandTotalMinor, ServerShop.salePrice);
    await expectLater(
      sell(t, quantity: ServerShop.openingStock, paid: ServerShop.salePrice * 1000),
      throwsA(isA<InsufficientStockException>()),
    );

    // Connectivity returns: the next tick pulls (an online tick would not).
    t.gateway.offline = false;
    expect(await remote.onTick(), isTrue);
    expect(remote.waitingForConnectivity, isFalse);
    expect(await remote.onTick(), isFalse, reason: 'online and idle: no extra pulls');
    expect(await catalogPrice(t), _newPrice);
    await expectLater(
      sell(t, quantity: 1000, paid: ServerShop.salePrice),
      throwsA(isA<SaleValidationException>()),
      reason: 'the old price no longer pays for the item',
    );
    expect((await sell(t, quantity: 1000, paid: _newPrice)).grandTotalMinor, _newPrice);

    // The offline sale keeps the price the customer paid when it uploads.
    final op = await (t.db.select(t.db.syncOperations)
          ..where((o) => o.entityId.equals(offlineSale.saleId)))
        .getSingle();
    final uploaded = await SupabaseSaleUploadGateway(t.shop.owner.client)
        .uploadSaleAggregate(jsonDecode(op.payload) as Map<String, dynamic>);
    expect((uploaded as Map)['status'], 'inserted');
    final row = await t.shop.owner.client
        .from('sales').select('grand_total').eq('id', offlineSale.saleId).single();
    expect(row['grand_total'], ServerShop.salePrice);
  }, skip: skip);
}

final class _Tablet {
  _Tablet(this.shop, this.deviceId, this.cashierId, this.db, this.gateway);
  final ServerShop shop;
  final String deviceId;
  final String cashierId;
  final AppDatabase db;
  final _Switchable gateway;

  /// The runtime's refresh pull: every POS entity, stopping at the first
  /// failure (pos_runtime_native.dart `_pullReferences`).
  Future<bool> pull() async {
    final service = ReferencePullService(db, gateway, shopId: shop.shopId);
    for (final entity in posPullEntities) {
      try {
        await service.pull(entity);
      } catch (_) {
        return false;
      }
    }
    return true;
  }
}

/// The real device gateway, or an offline device (socket error at once).
final class _Switchable implements ReferencePullGateway {
  _Switchable(this.inner);
  final ReferencePullGateway inner;
  bool offline = false;
  int calls = 0;

  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) {
    if (offline) {
      calls++;
      throw const SocketException('simulated offline tablet');
    }
    return inner.fetch(entity: entity, shopId: shopId, after: after, limit: limit);
  }
}
