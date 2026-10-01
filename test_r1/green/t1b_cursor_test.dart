// T-1b regression (cursor truncation), moved here from
// red/t1_local_and_t1b_cursor_red_test.dart by R1.4 with its name, rows and
// assertions unchanged. Pure local: no Docker, no network.
//
// The fake gateway models the server's paging contract. Before R1.4 that was
// (timestamp, id), and the device kept the timestamp with whole seconds, so
// rows inside one second came back forever. Since R1.4 the server pages by
// its own (server_seq, id), so the fake does too: rows m1 and m2 were written
// in one transaction (one position), m3 in the next. The same behaviour is
// proven against the real migrated server in direct_db/sync_order_test.dart.
@Tags(['r1-green'])
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:dukaan_pro/core/domain/enums.dart';
import 'package:dukaan_pro/database/app_database.dart';
import 'package:dukaan_pro/sync/pull/pull_models.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_gateway.dart';
import 'package:dukaan_pro/sync/pull/reference_pull_service.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppDatabase> _shopDb() async {
  final db = AppDatabase(NativeDatabase.memory());
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
  return db;
}

/// Server-like cursor semantics over rows whose timestamps carry microseconds.
final class _MicrosecondRowsGateway implements ReferencePullGateway {
  _MicrosecondRowsGateway(this.rows);
  final List<RemoteChange> rows;
  var fetches = 0;

  @override
  Future<List<RemoteChange>> fetch({
    required PullEntity entity,
    required String shopId,
    PullCursor? after,
    int limit = 100,
  }) async {
    fetches++;
    if (fetches > 20) {
      throw StateError('pull did not terminate after 20 fetches');
    }
    return rows
        .where(
          (r) =>
              after == null ||
              r.serverSeq > after.serverSeq ||
              (r.serverSeq == after.serverSeq &&
                  r.id.compareTo(after.entityId) > 0),
        )
        .take(limit)
        .toList();
  }
}

void main() {
  test('T-1b: rows sharing one second do not loop or re-fetch through a truncated cursor', () async {
    final db = await _shopDb();
    addTearDown(db.close);
    final second = DateTime.utc(2026, 9, 30, 10);
    final rows = [
      for (var i = 1; i <= 3; i++)
        RemoteChange(
          entity: PullEntity.inventoryMovements,
          id: 'm$i',
          shopId: 'shop',
          updatedAt: second.add(Duration(microseconds: i * 100000)),
          serverSeq: i < 3 ? 7 : 8,
          data: {
            'id': 'm$i',
            'shop_id': 'shop',
            'product_id': 'p',
            'type': 'sale',
            'quantity': -1000,
            'reference_type': 'sale',
            'reference_id': 's$i',
            'note': null,
            'created_by': 'owner',
            'device_id': 'device',
            'created_at': second.add(Duration(microseconds: i * 100000)).toIso8601String(),
          },
        ),
    ];
    final gateway = _MicrosecondRowsGateway(rows);
    Object? loopError;
    try {
      await ReferencePullService(db, gateway, shopId: 'shop')
          .pull(PullEntity.inventoryMovements, pageSize: 2);
    } catch (e) {
      loopError = e;
    }
    final cursor = await db.select(db.syncCursors).getSingleOrNull();
    // ignore: avoid_print
    print('T1B_EVIDENCE fetches=${gateway.fetches} error=$loopError '
        'stored cursor=${cursor?.updatedAt.toUtc().toIso8601String()} '
        '(rows at ${rows.map((r) => r.updatedAt.toIso8601String()).join(', ')})');
    // Two pages plus one empty page is the correct, bounded behaviour.
    expect(loopError, isNull);
    expect(gateway.fetches, lessThanOrEqualTo(3));
  });
}
