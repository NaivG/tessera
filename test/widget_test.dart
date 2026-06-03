import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const TesseraApp());
    // 应用启动后应显示加载指示器
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
