import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knockwater/main.dart';

Future<void> pumpSeconds(WidgetTester tester, double seconds) async {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('完整流程：入水 → 两次重叩 → 结算面板', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const KnockwaterApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('入 水'));
    await pumpSeconds(tester, 3.0);

    for (var i = 0; i < 2; i++) {
      final center = tester.getCenter(find.text('重叩'));
      final gesture = await tester.startGesture(center);
      await pumpSeconds(tester, 1.4);
      await gesture.up();
      await pumpSeconds(tester, 4.2);
    }
    await pumpSeconds(tester, 5.0);

    expect(find.text('湾心已满'), findsOneWidget);
    expect(find.text('下一关'), findsOneWidget);
  });
}
