import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import 'expense_models.dart';

final class DriftExpenseRepository {
  DriftExpenseRepository(this.db, {required this.shopId});
  final AppDatabase db;
  final String shopId;
  Future<List<ExpenseCategoryModel>> categories() async =>
      (await (db.select(db.expenseCategories)
                ..where(
                  (t) => t.shopId.equals(shopId) & t.isActive.equals(true),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.name)]))
              .get())
          .map((r) => ExpenseCategoryModel(id: r.id, name: r.name))
          .toList();
  Future<ExpenseSnapshot> query({
    String search = '',
    String? categoryId,
    DateTime? from,
    DateTime? to,
  }) async {
    final all =
        await (db.select(db.expenses)
              ..where((t) => t.shopId.equals(shopId))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day),
        monthStart = DateTime(now.year, now.month);
    final q = search.trim().toLowerCase();
    final rows = all
        .where((e) {
          final at = e.expenseAt ?? e.createdAt;
          return (categoryId == null || e.categoryId == categoryId) &&
              (from == null || !at.isBefore(from)) &&
              (to == null || at.isBefore(to.add(const Duration(days: 1)))) &&
              (q.isEmpty ||
                  e.description?.toLowerCase().contains(q) == true ||
                  e.category.toLowerCase().contains(q));
        })
        .map(
          (e) => ExpenseView(
            id: e.id,
            category: e.category,
            amountMinor: e.amount,
            paymentMethod: e.paymentMethod,
            description: e.description ?? '',
            expenseAt: e.expenseAt ?? e.createdAt,
            note: e.note,
            reference: e.reference,
          ),
        )
        .toList();
    return ExpenseSnapshot(
      rows: rows,
      todayMinor: all
          .where((e) => (e.expenseAt ?? e.createdAt).isAfter(dayStart))
          .fold(0, (s, e) => s + e.amount),
      monthMinor: all
          .where((e) => (e.expenseAt ?? e.createdAt).isAfter(monthStart))
          .fold(0, (s, e) => s + e.amount),
    );
  }
}
