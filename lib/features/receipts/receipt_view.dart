import 'package:flutter/material.dart';
import '../pos/pos_state.dart';
import 'receipt_model.dart';
import 'receipt_printer.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/bidi.dart';
import '../../core/l10n/product_names.dart';
import '../../core/l10n/localized_format.dart';
import '../../core/l10n/messages.dart';

class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.receipt});
  final ReceiptModel receipt;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String money(int minor) => bidiMoney(context, formatPkr(minor));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          bidiName(context, receipt.shopName),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (receipt.phone != null)
          Text(bidiId(context, receipt.phone!), textAlign: TextAlign.center),
        if (receipt.address != null)
          Text(
            bidiName(context, receipt.address!),
            textAlign: TextAlign.center,
          ),
        Text(bidiId(context, receipt.reference)),
        Text(
          l10n.receiptDateCashier(
            localizedDateTime(l10n, receipt.dateTime),
            bidiName(context, receipt.cashier),
          ),
        ),
        if (receipt.customer != null)
          Text(l10n.receiptCustomer(bidiName(context, receipt.customer!))),
        if (receipt.status != 'Completed')
          Text(
            localizedSaleStatus(l10n, receipt.status),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        const Divider(),
        for (final line in receipt.lines) ...[
          Text(
            l10n.receiptLine(
              bidiQuantity(
                context,
                localizedLineQuantity(l10n, line.quantity, line.measureUnit),
              ),
              productDisplayName(context, line.name),
              money(line.total),
            ),
          ),
          Text(
            '  ${l10n.receiptAtPrice(line.measureUnit == null ? l10n.receiptEach(money(line.unitPrice)) : localizedUnitPrice(l10n, money(line.unitPrice), line.measureUnit!))}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const Divider(),
        Text(l10n.receiptSubtotal(money(receipt.subtotal))),
        if (receipt.discount > 0)
          Text(
            l10n.receiptDiscount(
              bidiMoney(context, '-${formatPkr(receipt.discount)}'),
            ),
          ),
        Text(l10n.receiptTotal(money(receipt.total))),
        if (receipt.returned > 0)
          Text(l10n.receiptReturned(money(receipt.returned))),
        if (receipt.returned > 0)
          Text(l10n.receiptNet(money(receipt.netTotal))),
        for (final row in receipt.payments.entries)
          Text(
            l10n.receiptPayment(
              localizedPaymentMethod(l10n, row.key),
              money(row.value),
            ),
          ),
        if (receipt.received != null)
          Text(l10n.receiptReceived(money(receipt.received!))),
        if (receipt.change > 0) Text(l10n.receiptChange(money(receipt.change))),
        if (receipt.footer?.isNotEmpty == true) ...[
          const Divider(),
          Text(bidiName(context, receipt.footer!), textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

Future<void> showPrintableReceipt(
  BuildContext context,
  ReceiptModel receipt, {
  ReceiptPrinter printer = const UnavailableReceiptPrinter(),
  ReceiptPaperWidth width = ReceiptPaperWidth.mm80,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(context.l10n.receiptTitle),
    content: SingleChildScrollView(child: ReceiptView(receipt: receipt)),
    actions: [
      OutlinedButton.icon(
        icon: const Icon(Icons.print_outlined),
        label: Text(context.l10n.receiptPrint),
        onPressed: () async {
          final result = await printer.print(receipt, paperWidth: width);
          if (dialogContext.mounted) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              SnackBar(
                content: Text(localizedMessage(context.l10n, result.message)),
              ),
            );
          }
        },
      ),
      FilledButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(context.l10n.commonClose),
      ),
    ],
  ),
);
