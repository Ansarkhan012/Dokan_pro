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
    this.imagePath,
  });

  final String id;
  final String name;
  final String unit;
  final String? barcode;
  final String? imagePath;
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
    this.referenceType,
    this.reference,
  });

  final String id;
  final String productName;
  final InventoryMovementType type;
  final int quantity;
  final String? note;
  final DateTime createdAt;

  /// Stored origin (`sale`, `sale_return`, `sale_void`, `purchase`,
  /// `manual_inventory`), or null for movements without one.
  final String? referenceType;

  /// Human-readable document reference when one exists locally, such as
  /// `Bill #0509F516` or a supplier invoice number. Never invented.
  final String? reference;
}

enum InventoryFilter { all, lowStock, outOfStock }
