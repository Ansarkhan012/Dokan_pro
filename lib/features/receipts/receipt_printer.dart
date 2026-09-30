import 'receipt_model.dart';

final class ReceiptPrintResult {
  const ReceiptPrintResult({required this.printed, required this.message});
  final bool printed;
  final String message;
}

abstract interface class ReceiptPrinter {
  Future<ReceiptPrintResult> print(
    ReceiptModel receipt, {
    required ReceiptPaperWidth paperWidth,
  });
}

/// Safe default used until a supported Windows/Android transport is selected.
/// It deliberately reports unavailability and never participates in a sale
/// transaction, so a disconnected printer cannot roll a sale back.
final class UnavailableReceiptPrinter implements ReceiptPrinter {
  const UnavailableReceiptPrinter();
  @override
  Future<ReceiptPrintResult> print(
    ReceiptModel receipt, {
    required ReceiptPaperWidth paperWidth,
  }) async => const ReceiptPrintResult(
    printed: false,
    message: 'No receipt printer is configured. You can retry from Sales.',
  );
}
