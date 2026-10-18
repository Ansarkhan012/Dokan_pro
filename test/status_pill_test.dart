import 'package:dukaan_pro/core/ui/pos_ui.dart';
import 'package:dukaan_pro/features/pos/pos_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a long status label ellipsizes instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: StatusPill(
                'Saved on this tablet • Waiting to sync',
                tone: StatusTone.info,
                icon: Icons.cloud_queue,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(StatusPill)).width, lessThanOrEqualTo(120));
  });

  testWidgets('a short label keeps the pill compact', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatusPill('Synced', tone: StatusTone.success),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(StatusPill)).width, lessThan(200));
  });

  testWidgets('the sale receipt dialog fits a tablet at a large font scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1280, 800),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: ReceiptDialog(receipt: null, synced: false, onView: () {}),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Waiting to sync'), findsOneWidget);
  });
}
