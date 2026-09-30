enum ReportRangePreset { today, week, month, year, custom }

final class ReportRange {
  const ReportRange(this.startUtc, this.endUtc, {required this.label});
  final DateTime startUtc, endUtc;
  final String label;
  static const _offset = Duration(hours: 5);
  static ReportRange forPreset(ReportRangePreset p, DateTime nowUtc) {
    final local = nowUtc.toUtc().add(_offset);
    DateTime start;
    switch (p) {
      case ReportRangePreset.today:
        start = DateTime.utc(local.year, local.month, local.day);
      case ReportRangePreset.week:
        start = DateTime.utc(
          local.year,
          local.month,
          local.day,
        ).subtract(Duration(days: local.weekday - 1));
      case ReportRangePreset.month:
        start = DateTime.utc(local.year, local.month);
      case ReportRangePreset.year:
        start = DateTime.utc(local.year);
      case ReportRangePreset.custom:
        throw ArgumentError('Custom range requires dates');
    }
    return ReportRange(
      start.subtract(_offset),
      DateTime.utc(
        local.year,
        local.month,
        local.day,
      ).add(const Duration(days: 1)).subtract(_offset),
      label: p.name,
    );
  }

  static ReportRange custom(DateTime firstLocal, DateTime lastLocal) =>
      ReportRange(
        DateTime.utc(
          firstLocal.year,
          firstLocal.month,
          firstLocal.day,
        ).subtract(_offset),
        DateTime.utc(
          lastLocal.year,
          lastLocal.month,
          lastLocal.day,
        ).add(const Duration(days: 1)).subtract(_offset),
        label: 'Custom',
      );
}

final class ReportSummary {
  const ReportSummary({
    required this.sales,
    required this.grossSales,
    required this.returns,
    required this.purchases,
    required this.cogs,
    required this.expenses,
    required this.receivables,
    required this.payables,
    required this.billCount,
    required this.purchaseCount,
    required this.cash,
    required this.digital,
    required this.credit,
    required this.purchasePaid,
    required this.purchaseCredit,
    required this.lowStockCount,
    required this.missingCostLines,
    required this.partialReturnCount,
  });
  final int sales,
      grossSales,
      returns,
      purchases,
      cogs,
      expenses,
      receivables,
      payables,
      billCount,
      purchaseCount,
      cash,
      digital,
      credit,
      purchasePaid,
      purchaseCredit,
      lowStockCount,
      missingCostLines;
  final int partialReturnCount;
  int get grossProfit => sales - cogs;
  int get netProfit => grossProfit - expenses;
  int get averageBill => billCount == 0 ? 0 : sales ~/ billCount;
}

final class ReportBucket {
  const ReportBucket(this.label, this.sales, this.purchases);
  final String label;
  final int sales, purchases;
}

final class RankedValue {
  const RankedValue(this.label, this.value, {this.secondary = 0});
  final String label;
  final int value, secondary;
}

final class CashierReport {
  const CashierReport(
    this.name,
    this.sales,
    this.bills,
    this.cash,
    this.digital,
    this.credit,
  );
  final String name;
  final int sales, bills, cash, digital, credit;
}

final class OwnerReport {
  const OwnerReport({
    required this.summary,
    required this.trend,
    required this.topSalesProducts,
    required this.topQuantityProducts,
    required this.topProfitProducts,
    required this.expensesByCategory,
    required this.expensesByMethod,
    required this.topDebtors,
    required this.topSuppliers,
    required this.lowStock,
    required this.cashiers,
  });
  final ReportSummary summary;
  final List<ReportBucket> trend;
  final List<RankedValue> topSalesProducts,
      topQuantityProducts,
      topProfitProducts,
      expensesByCategory,
      expensesByMethod,
      topDebtors,
      topSuppliers,
      lowStock;
  final List<CashierReport> cashiers;
}
