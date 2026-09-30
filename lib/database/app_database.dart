import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/domain/enums.dart';
import 'tables/catalog_tables.dart';
import 'tables/operations_tables.dart';
import 'tables/organization_tables.dart';
import 'tables/party_tables.dart';
import 'tables/transaction_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Shops,
    ShopUsers,
    Cashiers,
    Devices,
    Categories,
    MasterProducts,
    ShopProducts,
    Customers,
    CustomerLedgerEntries,
    Suppliers,
    SupplierLedgerEntries,
    Sales,
    SaleItems,
    SalePayments,
    SaleReturns,
    SaleReturnItems,
    SaleVoids,
    InventoryMovements,
    Purchases,
    PurchaseItems,
    PurchasePayments,
    ExpenseCategories,
    Expenses,
    CashierShifts,
    AuditLogs,
    SyncOperations,
    SyncCursors,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  static Future<AppDatabase> open() async {
    final directory = await getApplicationSupportDirectory();
    return AppDatabase(
      NativeDatabase.createInBackground(
        File(p.join(directory.path, 'dukaan_pro.sqlite')),
      ),
    );
  }

  @override
  int get schemaVersion => 10;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(shops, shops.allowNegativeStock);
        await m.createTable(cashiers);
      }
      if (from < 3) {
        await m.addColumn(devices, devices.updatedAt);
        await m.addColumn(masterProducts, masterProducts.isActive);
        await m.addColumn(syncOperations, syncOperations.leaseOwner);
        await m.addColumn(syncOperations, syncOperations.leaseExpiresAt);
        await m.addColumn(syncOperations, syncOperations.lastAttemptAt);
        await m.addColumn(syncOperations, syncOperations.nextAttemptAt);
        await m.addColumn(syncOperations, syncOperations.dependsOnOperationId);
        await m.createTable(syncCursors);
      }
      if (from < 4) {
        await m.addColumn(masterProducts, masterProducts.packLabel);
        await m.addColumn(shopProducts, shopProducts.categoryId);
        await m.addColumn(shopProducts, shopProducts.unit);
        await m.addColumn(shopProducts, shopProducts.packLabel);
        await m.addColumn(shopProducts, shopProducts.imagePath);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS shop_products_unique_master '
          'ON shop_products(shop_id, master_product_id) '
          'WHERE master_product_id IS NOT NULL',
        );
      }
      if (from < 5) {
        await m.addColumn(customers, customers.notes);
        await m.addColumn(
          customerLedgerEntries,
          customerLedgerEntries.paymentMethod,
        );
      }
      if (from < 6) {
        await m.addColumn(suppliers, suppliers.contactPerson);
        await m.addColumn(suppliers, suppliers.notes);
        await m.addColumn(
          supplierLedgerEntries,
          supplierLedgerEntries.paymentMethod,
        );
        await m.addColumn(purchases, purchases.deviceId);
        await m.addColumn(purchases, purchases.notes);
        await m.addColumn(purchases, purchases.paidAmount);
        await m.addColumn(purchaseItems, purchaseItems.productNameSnapshot);
        await m.createTable(purchasePayments);
      }
      if (from < 7) {
        await m.createTable(expenseCategories);
        await m.addColumn(expenses, expenses.categoryId);
        await m.addColumn(expenses, expenses.paymentMethod);
        await m.addColumn(expenses, expenses.note);
        await m.addColumn(expenses, expenses.reference);
        await m.addColumn(expenses, expenses.deviceId);
        await m.addColumn(expenses, expenses.expenseAt);
      }
      if (from < 8) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS sales_shop_invoice '
          'ON sales(shop_id, invoice_number)',
        );
      }
      if (from < 9) {
        await m.createTable(saleReturns);
        await m.createTable(saleReturnItems);
        await m.createTable(saleVoids);
      }
      if (from < 10) {
        await m.addColumn(shops, shops.defaultLowStockLevel);
        await m.addColumn(shops, shops.receiptFooter);
        await m.addColumn(shops, shops.receiptPaperWidth);
        await m.addColumn(shops, shops.receiptShowPhone);
        await m.addColumn(shops, shops.receiptShowAddress);
        await m.addColumn(shops, shops.notificationsEnabled);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS shop_products_unique_master '
        'ON shop_products(shop_id, master_product_id) '
        'WHERE master_product_id IS NOT NULL',
      );
    },
  );
}
