import 'package:drift/drift.dart';
import '../../core/domain/enums.dart';
import '../app_database.dart';

final class AccountingRepository {
  AccountingRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;

  Future<int> customerBalance(String customerId) async {
    final rows =
        await (db.select(db.customerLedgerEntries)..where(
              (t) => t.shopId.equals(shopId) & t.customerId.equals(customerId),
            ))
            .get();
    var total = 0;
    for (final row in rows) {
      total += row.amount.abs() * row.type.balanceSign;
    }
    return total;
  }

  Future<int> productStock(String productId) async {
    final rows =
        await (db.select(db.inventoryMovements)..where(
              (t) => t.shopId.equals(shopId) & t.productId.equals(productId),
            ))
            .get();
    var total = 0;
    for (final row in rows) {
      final sign = row.type.conventionalSign;
      total += sign == null ? row.quantity : row.quantity.abs() * sign;
    }
    return total;
  }
}
