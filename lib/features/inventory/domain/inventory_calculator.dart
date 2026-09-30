import '../../../core/domain/enums.dart';

final class InventoryDelta {
  const InventoryDelta(this.type, this.quantity);
  final InventoryMovementType type;
  final int quantity;

  int get signedQuantity {
    final sign = type.conventionalSign;
    return sign == null ? quantity : quantity.abs() * sign;
  }
}

int calculateStock(Iterable<InventoryDelta> movements) =>
    movements.fold(0, (stock, movement) => stock + movement.signedQuantity);
