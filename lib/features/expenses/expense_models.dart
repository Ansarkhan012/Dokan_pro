import '../../core/domain/enums.dart';

final class ExpenseCategoryModel {
  const ExpenseCategoryModel({required this.id, required this.name});
  final String id, name;
}

final class ExpenseDraft {
  const ExpenseDraft({
    required this.shopId,
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
    required this.paymentMethod,
    required this.description,
    required this.ownerId,
    required this.deviceId,
    required this.expenseAt,
    this.note,
    this.reference,
  });
  final String shopId, categoryId, categoryName, description, ownerId, deviceId;
  final int amountMinor;
  final PaymentMethod paymentMethod;
  final DateTime expenseAt;
  final String? note, reference;
}

final class CreatedExpense {
  const CreatedExpense(this.expenseId, this.operationId);
  final String expenseId, operationId;
}

final class ExpenseView {
  const ExpenseView({
    required this.id,
    required this.category,
    required this.amountMinor,
    required this.paymentMethod,
    required this.description,
    required this.expenseAt,
    this.note,
    this.reference,
  });
  final String id, category, description;
  final int amountMinor;
  final PaymentMethod paymentMethod;
  final DateTime expenseAt;
  final String? note, reference;
}

final class ExpenseSnapshot {
  const ExpenseSnapshot({
    required this.rows,
    required this.todayMinor,
    required this.monthMinor,
  });
  final List<ExpenseView> rows;
  final int todayMinor, monthMinor;
}
