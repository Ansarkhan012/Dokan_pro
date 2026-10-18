import 'dart:convert';

import 'package:pointycastle/digests/md5.dart';

import '../../l10n/app_localizations.dart';

/// The default expense categories created by the server's
/// `ensure_default_expense_categories`, each with a fixed id per shop:
/// `md5(shop_id || ':expense:' || lower(name))::uuid`.
const _defaults = [
  'Rent',
  'Electricity',
  'Gas',
  'Internet',
  'Salary',
  'Transport',
  'Delivery',
  'Maintenance',
  'Food/Tea',
  'Packaging',
  'Miscellaneous',
];

/// The stable id the server gives [name] in [shopId] (same formula).
String defaultExpenseCategoryId(String shopId, String name) {
  final digest = MD5Digest().process(
    utf8.encode('$shopId:expense:${name.toLowerCase()}'),
  );
  final hex = [
    for (final b in digest) b.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final _ids = <String, Map<String, String>>{};

/// A default category translated by its stable id; a shop's own category
/// (any other id) exactly as entered. Stored names never change.
String localizedExpenseCategory(
  AppLocalizations l10n, {
  required String shopId,
  required String id,
  required String name,
}) {
  final byId = _ids.putIfAbsent(
    shopId,
    () => {for (final n in _defaults) defaultExpenseCategoryId(shopId, n): n},
  );
  return switch (byId[id]) {
    'Rent' => l10n.expenseCatRent,
    'Electricity' => l10n.expenseCatElectricity,
    'Gas' => l10n.expenseCatGas,
    'Internet' => l10n.expenseCatInternet,
    'Salary' => l10n.expenseCatSalary,
    'Transport' => l10n.expenseCatTransport,
    'Delivery' => l10n.expenseCatDelivery,
    'Maintenance' => l10n.expenseCatMaintenance,
    'Food/Tea' => l10n.expenseCatFoodTea,
    'Packaging' => l10n.expenseCatPackaging,
    'Miscellaneous' => l10n.expenseCatMiscellaneous,
    _ => name,
  };
}
