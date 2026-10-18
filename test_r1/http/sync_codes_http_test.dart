// R1.5 HTTP contract (stable sync codes and record-and-flag), delivered by
// migration 202610020001 and moved from the expected-red suite unchanged in
// names and assertions, through the real Supabase HTTP path of a disposable
// local stack. Payloads are built by hand with explicit UTC instants so T-1
// cannot mask the contract under test.
@Tags(['r1-http'])
library;

import 'package:dukaan_pro/sync/sync_failure.dart';
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

/// The PostgREST error an RPC raised, classified exactly as the worker does.
Future<(String?, SyncFailureKind)> _classified(Future<Object?> Function() call) async {
  try {
    await call();
  } catch (e) {
    return (ServerError.of(e)?.code, classifySyncError(e).kind);
  }
  fail('the RPC was expected to reject the operation');
}

Map<String, dynamic> _payment(ServerShop shop, {required String entryId, int amount = 5000, String? note, String? deviceId}) {
  final at = _now();
  return {
    'version': 1,
    'operation': 'sync_customer_payment',
    'entry': {
      'id': entryId,
      'shop_id': shop.shopId,
      'customer_id': shop.customerId,
      'type': 'paymentReceived',
      'amount': amount,
      'payment_reference': null,
      'payment_method': 'cash',
      'note': note,
      'created_by': shop.owner.userId,
      'created_at': at,
    },
    'audit': {
      'id': _id(),
      'shop_id': shop.shopId,
      'user_id': shop.owner.userId,
      'action': 'customer.payment_received',
      'entity_type': 'customer_ledger_entry',
      'entity_id': entryId,
      'new_value': {'amount': amount, 'method': 'cash'},
      'device_id': deviceId ?? shop.deviceA,
      'created_at': at,
    },
  };
}

Map<String, dynamic> _void(ServerShop shop, Map<String, dynamic> sale, {required String voidId}) {
  final item = (sale['sale_items'] as List).single as Map;
  return {
    'version': 2,
    'operation': 'sync_sale_void',
    'void': {
      'id': voidId,
      'shop_id': shop.shopId,
      'original_sale_id': (sale['sale'] as Map)['id'],
      'device_id': shop.deviceA,
      'amount': ServerShop.salePrice,
      'reason': 'wrong item',
      'payment_breakdown': {'cash': ServerShop.salePrice},
      'created_by': shop.owner.userId,
      'created_at': _now(),
    },
    'movement_ids': {item['id']: _id()},
    'refund_ledger_id': null,
    'audit_id': _id(),
  };
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

  test('R1.5 codes reach the client classifier over HTTP: sale DPV01/DPC01 permanent, DPA01 auth', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    expect(await _classified(() => _rpc(shop, 'sync_sale_transaction', _sale(shop, saleId: _id(), amount: 0))),
        ('DPV01', SyncFailureKind.permanent));
    final saleId = _id();
    final original = _sale(shop, saleId: saleId);
    await _rpc(shop, 'sync_sale_transaction', original);
    final changed = {
      ...original,
      'sale': {...(original['sale'] as Map<String, dynamic>), 'invoiceNumber': 'CHANGED'},
    };
    expect(await _classified(() => _rpc(shop, 'sync_sale_transaction', changed)), ('DPC01', SyncFailureKind.permanent));
    await shop.owner.client.from('devices').update({'is_active': false}).eq('id', shop.deviceB);
    expect(await _classified(() => _rpc(shop, 'sync_sale_transaction', _sale(shop, saleId: _id(), deviceId: shop.deviceB))),
        ('DPA01', SyncFailureKind.auth));
  }, skip: skip);

  test('R1.5 customer payment over HTTP: DPV01 and DPC01 permanent, revoked device DPA01 auth', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    await _rpc(shop, 'sync_sale_transaction',
        _sale(shop, saleId: _id(), method: 'credit', customerId: shop.customerId)); // Udhaar to pay
    final entryId = _id();
    await _rpc(shop, 'sync_customer_payment', _payment(shop, entryId: entryId));
    expect(await _classified(() => _rpc(shop, 'sync_customer_payment', _payment(shop, entryId: _id(), amount: 0))),
        ('DPV01', SyncFailureKind.permanent));
    expect(await _classified(() => _rpc(shop, 'sync_customer_payment', _payment(shop, entryId: entryId, note: 'changed'))),
        ('DPC01', SyncFailureKind.permanent));
    await shop.owner.client.from('devices').update({'is_active': false}).eq('id', shop.deviceB);
    expect(await _classified(() => _rpc(shop, 'sync_customer_payment', _payment(shop, entryId: _id(), deviceId: shop.deviceB))),
        ('DPA01', SyncFailureKind.auth));
  }, skip: skip);

  test('R1.5 void over HTTP: a second void is DPX01 permanent; a changed replay DPC01 permanent', () async {
    final shop = await ServerShop.create(await stack.signUpOwner());
    final sale = _sale(shop, saleId: _id());
    await _rpc(shop, 'sync_sale_transaction', sale);
    final voidId = _id();
    final first = _void(shop, sale, voidId: voidId);
    await _rpc(shop, 'sync_sale_void', first);
    expect(await _classified(() => _rpc(shop, 'sync_sale_void', _void(shop, sale, voidId: _id()))),
        ('DPX01', SyncFailureKind.permanent));
    final changed = {...first, 'void': {...(first['void'] as Map<String, dynamic>), 'reason': 'changed'}};
    expect(await _classified(() => _rpc(shop, 'sync_sale_void', changed)), ('DPC01', SyncFailureKind.permanent));
    final voids = await shop.owner.client.from('sale_voids').select('id').eq('original_sale_id', (sale['sale'] as Map)['id']) as List;
    expect(voids, hasLength(1));
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
