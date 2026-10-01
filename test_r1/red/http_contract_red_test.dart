// Expected-red HTTP contract tests for R1.5 (the R1.3 v2 void and R1.4 server_seq
// tests moved to the green HTTP layer when their stages delivered them), through the real Supabase
// HTTP path of a disposable local stack. Payloads are built by hand with
// explicit UTC instants so T-1 cannot mask the contract under test. Missing
// contracts are converted into `fail()` so each test is red for the intended
// reason, never for a harness error.
@Tags(['recovery-red', 'r1-http'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../support/http_stack.dart';

String _id() => const Uuid().v4();
String _now() => DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _sale(
  ServerShop shop, {
  required String saleId,
  String? deviceId,
  String method = 'cash',
  int amount = ServerShop.salePrice,
  String? customerId,
  Map<String, dynamic>? overrideSale,
}) {
  final at = _now();
  final itemId = _id();
  return {
    'version': 1,
    'operation': 'sync_sale_transaction',
    'audit_id': _id(),
    'sale': {
      'id': saleId,
      'shopId': shop.shopId,
      'cashierId': shop.owner.userId,
      'customerId': customerId,
      'deviceId': deviceId ?? shop.deviceA,
      'invoiceNumber': null,
      'subtotal': ServerShop.salePrice,
      'discountTotal': 0,
      'taxTotal': 0,
      'grandTotal': ServerShop.salePrice,
      'paymentStatus': 'paid',
      'saleStatus': 'completed',
      'createdAt': at,
      ...?overrideSale,
    },
    'sale_items': [
      {
        'id': itemId,
        'productId': shop.productId,
        'productNameSnapshot': 'Coke',
        'barcodeSnapshot': null,
        'quantity': 1000,
        'costPriceSnapshot': 15000,
        'salePriceSnapshot': ServerShop.salePrice,
        'discountAmount': 0,
        'lineTotal': ServerShop.salePrice,
        'createdAt': at,
      },
    ],
    'payments': [
      {'id': _id(), 'paymentMethod': method, 'amount': amount, 'reference': null, 'createdAt': at},
    ],
    'inventory_movements': [
      {'id': _id(), 'productId': shop.productId, 'type': 'sale', 'quantity': -1000, 'createdAt': at},
    ],
    'customer_ledger_entries': [
      if (method == 'credit')
        {'id': _id(), 'customerId': customerId, 'amount': amount, 'createdAt': at},
    ],
  };
}

Future<Object?> _rpc(ServerShop shop, String name, Map<String, dynamic> payload) =>
    shop.owner.client.rpc(name, params: {'p_payload': payload, 'p_cashier_token': null});

Future<String> _codeOf(Future<Object?> Function() call) async {
  try {
    await call();
    return 'no error';
  } catch (e) {
    return ServerError.of(e)?.code ?? 'non-PostgREST error: $e';
  }
}

void main() {
  late LocalHttpStack stack;
  setUpAll(() async {
    if (r1HttpConfigured) stack = await LocalHttpStack.connect();
  });
  tearDownAll(() async {
    if (r1HttpConfigured) await stack.dispose();
  });
  const skip = r1HttpConfigured ? false : r1HttpSkipReason;

  test('R1.5 DPV01: a zero-amount payment row is rejected with stable code DPV01', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final code = await _codeOf(
      () => _rpc(shop, 'sync_sale_transaction', _sale(shop, saleId: _id(), amount: 0)),
    );
    // ignore: avoid_print
    print('DPV01_EVIDENCE observed code=$code');
    expect(code, 'DPV01');
  }, skip: skip);

  test('R1.5 DPC01: same sale id with different content is rejected with DPC01', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final saleId = _id();
    final original = _sale(shop, saleId: saleId);
    await _rpc(shop, 'sync_sale_transaction', original);
    final changed = {
      ...original,
      'sale': {...(original['sale'] as Map<String, dynamic>), 'invoiceNumber': 'CHANGED'},
    };
    final code = await _codeOf(() => _rpc(shop, 'sync_sale_transaction', changed));
    // ignore: avoid_print
    print('DPC01_EVIDENCE observed code=$code');
    expect(code, 'DPC01');
  }, skip: skip);

  test('R1.5 DPA01: a sale from a revoked device is rejected with DPA01', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    await shop.owner.client.from('devices').update({'is_active': false}).eq('id', shop.deviceB);
    final code = await _codeOf(
      () => _rpc(shop, 'sync_sale_transaction', _sale(shop, saleId: _id(), deviceId: shop.deviceB)),
    );
    // ignore: avoid_print
    print('DPA01_EVIDENCE observed code=$code');
    expect(code, 'DPA01');
  }, skip: skip);

  test('R1.5 accepted_flagged: offline credit sale over the limit is recorded and flagged', () async {
    final shop = await ServerShop.create(await stack.signUpOwner(), creditLimit: 30000);
    Map<String, dynamic> credit() => _sale(
          shop,
          saleId: _id(),
          method: 'credit',
          customerId: shop.customerId,
        );
    await _rpc(shop, 'sync_sale_transaction', credit());
    Object? result;
    try {
      result = await _rpc(shop, 'sync_sale_transaction', credit());
    } catch (e) {
      fail('second offline credit sale was rejected instead of accepted_flagged: '
          '${ServerError.of(e) ?? e}');
    }
    expect((result as Map)['status'], 'accepted_flagged');
  }, skip: skip);
}
