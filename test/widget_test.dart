import 'package:flutter_test/flutter_test.dart';
import 'package:scrollauto/main.dart';

void main() {
  testWidgets('App renders title', (tester) async {
    await tester.pumpWidget(const DoomApp());
    expect(find.text('Doom'), findsWidgets);
  });
}
