import '../../core/domain/enums.dart';

final class InventoryProductRow {
  const InventoryProductRow({
    required this.id,
    required this.name,
    required this.unit,
    required this.stockQuantity,
    required this.lowStockLevel,
    required this.isActive,
    this.barcode,
  });

  final String id;
  final String name;
  final String unit;
  final String? barcode;
  final int stockQuantity;
  final int? lowStockLevel;
  final bool isActive;

  bool get isOutOfStock => stockQuantity <= 0;
  bool get isLowStock =>
      !isOutOfStock && lowStockLevel != null && stockQuantity <= lowStockLevel!;
}

final class InventoryMovementRow {
  const InventoryMovementRow({
    required this.id,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String productName;
  final InventoryMovementType type;
  final int quantity;
  final String? note;
  final DateTime createdAt;
}

enum InventoryFilter { all, lowStock, outOfStock }
