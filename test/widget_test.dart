import 'package:dukaan_pro/app/dukaan_pro_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('unconfigured development shell explains required config', (
    tester,
  ) async {
    await tester.pumpWidget(const DukaanProApp());
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });
}
