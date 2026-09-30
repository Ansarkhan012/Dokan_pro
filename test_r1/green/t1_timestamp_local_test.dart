// R1.2 timestamp correctness (T-1), local layer: every instant that leaves
// the device is unambiguous RFC 3339 UTC ('Z'), equal to the real event
// instant whatever the device time zone. Run under TZ=UTC, Asia/Karachi and a
// negative offset (EST5): expectations are fixed literals, never re-derived
// with the conversion under test.
//
// 'T-1 (local)' moved here from red/t1_local_and_t1b_cursor_red_test.dart by
// R1.2 with its name and assertion unchanged.
@Tags(['r1-green'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/core/ids/id_generator.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/database/repositories/sync_queue_repository.dart';
import 'package:dukaan_pro/features/purchases/local_purchase_service.dart';
import 'package:dukaan_pro/features/purchases/purchase_models.dart';
import 'package:dukaan_pro/features/reports/report_models.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_service.dart';
import 'package:dukaan_pro/features/sales/application/local_sale_void_service.dart';
import 'package:dukaan_pro/features/sales/domain/sale_draft.dart';
import 'package:dukaan_pro/features/sales/sales_history.dart';
import 'package:dukaan_pro/sync/sale_payload_codec.dart';
import 'package:dukaan_pro/sync/sale_upload_gateway.dart';
import 'package:dukaan_pro/sync/sync_time.dart';
import 'package:dukaan_pro/sync/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppDatabase> _shopDb([QueryExecutor? executor]) async {
  final db = AppDatabase(executor ?? NativeDatabase.memory());
  final t = DateTime.utc(2026, 9, 1);
  await db.into(db.shops).insert(ShopsCompanion.insert(
    id: 'shop', name: 'Shop', phone: '', address: '',
    subscriptionPlan: SubscriptionPlan.trial,
    subscriptionStatus: SubscriptionStatus.trial,
    createdAt: t, updatedAt: t,
  ));
  await db.into(db.shopUsers).insert(ShopUsersCompanion.insert(
    id: 'm', shopId: 'shop', userId: 'owner', role: ShopRole.owner, createdAt: t,
  ));
  await db.into(db.devices).insert(DevicesCompanion.insert(
    id: 'device', shopId: 'shop', deviceName: 'd',
    deviceType: DeviceType.androidTablet, deviceIdentifier: 'd', createdAt: t,
  ));
  await db.into(db.shopProducts).insert(ShopProductsCompanion.insert(
    id: 'p', shopId: 'shop', customName: const Value('Coke'),
    purchasePrice: 15000, salePrice: 18000, createdAt: t, updatedAt: t,
  ));
  await db.into(db.customers).insert(CustomersCompanion.insert(
    id: 'c', shopId: 'shop', name: 'Ahmed', createdAt: t, updatedAt: t,
  ));
  await db.into(db.suppliers).insert(SuppliersCompanion.insert(
    id: 's', shopId: 'shop', name: 'Supplier', createdAt: t, updatedAt: t,
  ));
  return db;
}

/// 10:00 in Pakistan (UTC+05:00) on 30 Sep 2026.
final _tenAmKarachi = DateTime.utc(2026, 9, 30, 5);
const _tenAmKarachiWire = '2026-09-30T05:00:00.000Z';

Future<CreatedSale> _sell(AppDatabase db, DateTime at, {bool udhaar = false}) =>
    LocalSaleService(db, const UuidV7Generator(), clock: () => at).createSale(SaleDraft(
      shopId: 'shop',
      cashierId: 'owner',
      deviceId: 'device',
      customerId: udhaar ? 'c' : null,
      lines: const [SaleLineDraft(productId: 'p', quantity: 1000)],
      payments: [
        SalePaymentDraft(method: udhaar ? PaymentMethod.credit : PaymentMethod.cash, amountMinor: 18000),
      ],
    ));

Future<Map<String, dynamic>> _queued(AppDatabase db, String entityId) async => jsonDecode(
      (await (db.select(db.syncOperations)..where((t) => t.entityId.equals(entityId))).getSingle())
          .payload,
    ) as Map<String, dynamic>;

/// Every timestamp string in a payload, with its JSON path.
Map<String, String> _stamps(Object? value, [String path = r'$']) {
  final out = <String, String>{};
  if (value is Map) {
    value.forEach((k, v) => out.addAll(_stamps(v, '$path.$k')));
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      out.addAll(_stamps(value[i], '$path[$i]'));
    }
  } else if (value is String && RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}').hasMatch(value)) {
    out[path] = value;
  }
  return out;
}

/// The production upload boundary in front of a recorder (no network).
final class _CloudBoundary implements SaleUploadGateway {
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> uploadSaleAggregate(Map<String, dynamic> payload, {String? cashierSessionToken}) async =>
      sent.add(payloadForCloud(payload));
}

/// Expected local wall-clock hour of 05:00Z for the matrix zones.
int? _localHourOfFiveZ() => const {300: 10, 0: 5, -300: 0}[DateTime.now().timeZoneOffset.inMinutes];

void main() {
  // Moved unchanged from the expected-red suite (T-1 fixed by R1.2).
  test('T-1 (local): uploaded sale timestamp is the real instant on this device', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final soldAt = DateTime.utc(2026, 9, 30, 4, 59, 26);
    await LocalSaleService(db, const UuidV7Generator(), clock: () => soldAt).createSale(
      const SaleDraft(
        shopId: 'shop',
        cashierId: 'owner',
        deviceId: 'device',
        lines: [SaleLineDraft(productId: 'p', quantity: 1000)],
        payments: [SalePaymentDraft(method: PaymentMethod.cash, amountMinor: 18000)],
      ),
    );
    final queued = await db.select(db.syncOperations).getSingle();
    final uploaded = normalizeSalePayloadForCloud(
      jsonDecode(queued.payload) as Map<String, dynamic>,
    );
    final uploadedAt = DateTime.parse((uploaded['sale'] as Map)['createdAt'] as String);
    // ignore: avoid_print
    print('T1_LOCAL_EVIDENCE zone=${DateTime.now().timeZoneName} '
        'offset=${DateTime.now().timeZoneOffset} real=${soldAt.toIso8601String()} '
        'uploaded=${uploadedAt.toIso8601String()} skew=${uploadedAt.difference(soldAt)}');
    expect(uploadedAt.difference(soldAt), Duration.zero);
  });

  test('the matrix zone is one of UTC, Asia/Karachi or EST5', () {
    expect(_localHourOfFiveZ(), isNotNull, reason: 'offset ${DateTime.now().timeZoneOffset}');
  });

  test('A: a 10:00 Pakistan Udhaar sale is queued and uploaded as 05:00Z in every row', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final sale = await _sell(db, _tenAmKarachi, udhaar: true);
    final queued = await _queued(db, sale.saleId);
    final stamps = _stamps(queued);
    // sale, item, payment, stock movement and Udhaar ledger entry.
    expect(stamps.keys, containsAll([
      r'$.sale.createdAt',
      r'$.sale_items[0].createdAt',
      r'$.payments[0].createdAt',
      r'$.inventory_movements[0].createdAt',
      r'$.customer_ledger_entries[0].createdAt',
    ]));
    expect(stamps.values.toSet(), {_tenAmKarachiWire}, reason: '$stamps');
    expect(_stamps(payloadForCloud(queued)).values.toSet(), {_tenAmKarachiWire});

    // Read back locally: the same instant, 10:00 on the Pakistan business day.
    final history = DriftSalesHistoryRepository(db, shopId: 'shop');
    final row = (await history.sale(sale.saleId))!;
    expect(row.at, DateTime.utc(2026, 9, 30, 5));
    expect(row.at.toLocal().hour, _localHourOfFiveZ());
    final pakistanDay = ReportRange.forPreset(ReportRangePreset.today, _tenAmKarachi);
    expect(pakistanDay.startUtc, DateTime.utc(2026, 9, 29, 19));
    expect((await history.page(filter: SaleHistoryFilter(range: pakistanDay))).map((r) => r.id), [sale.saleId]);
  });

  test('A: a 10:00 Pakistan purchase is queued as 05:00Z in every row', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final purchase = await LocalPurchaseService(db, const UuidV7Generator(), clock: () => _tenAmKarachi).create(
      const PurchaseDraft(
        shopId: 'shop',
        supplierId: 's',
        deviceId: 'device',
        ownerId: 'owner',
        lines: [PurchaseLineDraft(productId: 'p', quantity: 2000, unitCostMinor: 15000)],
        payments: [PurchasePaymentDraft(method: PaymentMethod.cash, amountMinor: 10000)],
      ),
    );
    final op = await (db.select(db.syncOperations)
          ..where((t) => t.entityType.equals('purchase_aggregate') | t.entityId.equals(purchase.purchaseId)))
        .getSingle();
    final stamps = _stamps(jsonDecode(op.payload));
    expect(stamps, isNotEmpty);
    expect(stamps.values.toSet(), {_tenAmKarachiWire}, reason: '$stamps');
  });

  test('B: the wire instant is independent of how the DateTime was held', () {
    final asUtc = DateTime.utc(2026, 9, 30, 5);
    final asLocal = asUtc.toLocal();
    final fromEpoch = DateTime.fromMillisecondsSinceEpoch(asUtc.millisecondsSinceEpoch);
    for (final value in [asUtc, asLocal, fromEpoch]) {
      expect(SyncTime.encode(value), _tenAmKarachiWire);
    }
    expect(SyncTime.hasExplicitOffset('2026-09-30T05:00:00.000Z'), isTrue);
    expect(SyncTime.hasExplicitOffset('2026-09-30T10:00:00+05:00'), isTrue);
    expect(SyncTime.hasExplicitOffset('2026-09-30T00:00:00.000-0500'), isTrue);
    expect(SyncTime.hasExplicitOffset('2026-09-30T10:00:00.000'), isFalse);
  });

  test('C: sales around midnight in Pakistan keep their UTC and Pakistan calendar dates', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final beforeMidnight = await _sell(db, DateTime.utc(2026, 9, 30, 18, 30)); // 23:30 PKT 30 Sep
    final afterMidnight = await _sell(db, DateTime.utc(2026, 9, 30, 19, 30)); // 00:30 PKT 1 Oct
    expect(((await _queued(db, beforeMidnight.saleId))['sale'] as Map)['createdAt'], '2026-09-30T18:30:00.000Z');
    expect(((await _queued(db, afterMidnight.saleId))['sale'] as Map)['createdAt'], '2026-09-30T19:30:00.000Z');
    final history = DriftSalesHistoryRepository(db, shopId: 'shop');
    final sep30 = ReportRange.forPreset(ReportRangePreset.today, DateTime.utc(2026, 9, 30, 12));
    final oct1 = ReportRange.forPreset(ReportRangePreset.today, DateTime.utc(2026, 10, 1, 1));
    expect((sep30.startUtc, sep30.endUtc), (DateTime.utc(2026, 9, 29, 19), DateTime.utc(2026, 9, 30, 19)));
    expect((await history.page(filter: SaleHistoryFilter(range: sep30))).map((r) => r.id), [beforeMidnight.saleId]);
    expect((await history.page(filter: SaleHistoryFilter(range: oct1))).map((r) => r.id), [afterMidnight.saleId]);
  });

  test('D: an offline sale keeps its event instant through restart and a later upload', () async {
    final dir = Directory.systemTemp.createTempSync('r1_2_offline_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}pos.sqlite');
    final db = await _shopDb(NativeDatabase(file));
    final sale = await _sell(db, _tenAmKarachi);
    final queuedBefore = (await db.select(db.syncOperations).getSingle()).payload;
    await db.close(); // offline; the process ends

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final uploadAt = _tenAmKarachi.add(const Duration(hours: 3));
    final boundary = _CloudBoundary();
    final result = await SyncWorker(
      queue: SyncQueueRepository(reopened, shopId: 'shop'),
      gateway: boundary,
      workerId: 'device',
      clock: () => uploadAt,
    ).runOnce();
    expect(result.synced, 1);
    final op = await reopened.select(reopened.syncOperations).getSingle();
    expect(op.payload, queuedBefore, reason: 'the queued payload is never rewritten');
    expect(op.syncedAt!.isAtSameMomentAs(uploadAt), isTrue, reason: '${op.syncedAt}');
    final sent = boundary.sent.single;
    expect((sent['sale'] as Map)['createdAt'], _tenAmKarachiWire, reason: 'event time, not upload time');
    expect(_stamps(sent).values.toSet(), {_tenAmKarachiWire});
    final stored = await (reopened.select(reopened.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
    expect(stored.createdAt.isAtSameMomentAs(_tenAmKarachi), isTrue);
  });

  test('G: the local void window compares real instants (14:59 allowed, 15:01 refused)', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    Future<Object?> voidAt(Duration after) async {
      final sale = await _sell(db, _tenAmKarachi);
      try {
        await LocalSaleVoidService(db, const UuidV7Generator(), clock: () => _tenAmKarachi.add(after))
            .voidSale(shopId: 'shop', saleId: sale.saleId, ownerId: 'owner', deviceId: 'device', reason: 'wrong');
        return null;
      } catch (e) {
        return e;
      }
    }

    expect(await voidAt(const Duration(minutes: 14, seconds: 59)), isNull);
    expect('${await voidAt(const Duration(minutes: 15, seconds: 1))}', contains('void window has expired'));
    final voidOp = (await db.select(db.syncOperations).get()).singleWhere((o) => o.entityType.contains('void'));
    final voidStamps = _stamps(jsonDecode(voidOp.payload)).values.toSet();
    expect(voidStamps, {'2026-09-30T05:14:59.000Z'});
  });

  group('legacy queued payloads (pre-R1.2) are never guessed', () {
    Future<(AppDatabase, String, String)> legacySale() async {
      final db = await _shopDb();
      final sale = await _sell(db, _tenAmKarachi);
      // Exactly what pre-R1.2 code queued: Drift's default string encoding,
      // which writes the local wall clock without any offset.
      const legacy = ValueSerializer.defaults(serializeDateTimeValuesAsString: true);
      final row = await (db.select(db.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
      final payload = await _queued(db, sale.saleId);
      payload['sale'] = row.toJson(serializer: legacy);
      final text = jsonEncode(payload);
      await (db.update(db.syncOperations)..where((t) => t.entityId.equals(sale.saleId)))
          .write(SyncOperationsCompanion(payload: Value(text)));
      return (db, sale.saleId, text);
    }

    test('an offset-less queued sale is refused, kept byte-identical and never marked synced', () async {
      final (db, saleId, text) = await legacySale();
      addTearDown(db.close);
      final ambiguous = (jsonDecode(text)['sale'] as Map)['createdAt'] as String;
      expect(SyncTime.hasExplicitOffset(ambiguous), isFalse, reason: ambiguous);
      final saleBefore = await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingle();
      final boundary = _CloudBoundary();
      final result = await SyncWorker(
        queue: SyncQueueRepository(db, shopId: 'shop'),
        gateway: boundary,
        workerId: 'device',
      ).runOnce();
      expect(result.synced, 0);
      expect(boundary.sent, isEmpty, reason: 'nothing reaches the server');
      final op = await db.select(db.syncOperations).getSingle();
      expect(op.status, SyncStatus.failed);
      expect(op.lastError, contains('AmbiguousTimestampPayload'));
      expect(op.payload, text, reason: 'no silent rewrite');
      final saleAfter = await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingle();
      expect(saleAfter, saleBefore);
    });

    test('offset-less timestamps are refused for every operation type', () {
      for (final operation in ['sync_sale_transaction', 'sync_purchase_transaction', 'sync_expense']) {
        expect(
          () => payloadForCloud({
            'operation': operation,
            'row': {'createdAt': '2026-09-30T10:00:00.000'},
          }),
          throwsA(isA<AmbiguousTimestampPayload>()),
          reason: operation,
        );
      }
    });

    test('unambiguous legacy encodings keep their instant', () {
      final epoch = normalizeSalePayloadForCloud({
        'operation': 'sync_sale_transaction',
        'sale': {'createdAt': DateTime.utc(2026, 9, 30, 5).millisecondsSinceEpoch},
      });
      expect((epoch['sale'] as Map)['createdAt'], _tenAmKarachiWire);
      final offset = payloadForCloud({
        'operation': 'sync_sale_transaction',
        'sale': {'createdAt': '2026-09-30T10:00:00.000+05:00'},
      });
      expect((offset['sale'] as Map)['createdAt'], _tenAmKarachiWire);
      final other = {
        'operation': 'sync_expense',
        'expense': {'created_at': '2026-09-30T05:00:00.000Z', 'expense_at': '2026-09-30T05:00:00.000Z'},
      };
      expect(payloadForCloud(other), other, reason: 'already explicit payloads are sent unchanged');
    });
  });
}
