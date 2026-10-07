import 'package:flutter/material.dart';
import '../../core/format/display_format.dart';
import '../pos/pos_state.dart';
import 'receipt_model.dart';
import 'receipt_printer.dart';

class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.receipt});
  final ReceiptModel receipt;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        receipt.shopName,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (receipt.phone != null)
        Text(receipt.phone!, textAlign: TextAlign.center),
      if (receipt.address != null)
        Text(receipt.address!, textAlign: TextAlign.center),
      Text(receipt.reference),
      Text('${formatDisplayDateTime(receipt.dateTime)} • ${receipt.cashier}'),
      if (receipt.customer != null) Text('Customer: ${receipt.customer}'),
      if (receipt.status != 'Completed')
        Text(
          receipt.status,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      const Divider(),
      for (final line in receipt.lines)
        Text(
          '${line.quantity / quantityScale} × ${line.name}  ${formatPkr(line.total)}',
        ),
      const Divider(),
      Text('Subtotal ${formatPkr(receipt.subtotal)}'),
      Text('Total ${formatPkr(receipt.total)}'),
      if (receipt.returned > 0) Text('Returned ${formatPkr(receipt.returned)}'),
      if (receipt.returned > 0) Text('Net ${formatPkr(receipt.netTotal)}'),
      for (final row in receipt.payments.entries)
        Text('${paymentMethodLabel(row.key)}: ${formatPkr(row.value)}'),
      if (receipt.received != null)
        Text('Received ${formatPkr(receipt.received!)}'),
      if (receipt.change > 0) Text('Change ${formatPkr(receipt.change)}'),
      if (receipt.footer?.isNotEmpty == true) ...[
        const Divider(),
        Text(receipt.footer!, textAlign: TextAlign.center),
      ],
    ],
  );
}

Future<void> showPrintableReceipt(
  BuildContext context,
  ReceiptModel receipt, {
  ReceiptPrinter printer = const UnavailableReceiptPrinter(),
  ReceiptPaperWidth width = ReceiptPaperWidth.mm80,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Receipt'),
    content: SingleChildScrollView(child: ReceiptView(receipt: receipt)),
    actions: [
      OutlinedButton.icon(
        icon: const Icon(Icons.print_outlined),
        label: const Text('Print / Reprint'),
        onPressed: () async {
          final result = await printer.print(receipt, paperWidth: width);
          if (dialogContext.mounted) {
            ScaffoldMessenger.of(
              dialogContext,
            ).showSnackBar(SnackBar(content: Text(result.message)));
          }
        },
      ),
      FilledButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Close'),
      ),
    ],
  ),
);
