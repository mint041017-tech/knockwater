import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knockwater/main.dart';

Future<void> pumpSeconds(WidgetTester tester, double seconds) async {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('完整流程：标题→入水→走步→撤销→重叩→结算→下一关', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const KnockwaterApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('入 水'), findsOneWidget);

    await tester.tap(find.text('入 水'));
    await pumpSeconds(tester, 3.2);

    // 走一步：键盘路径与拖拽共用 _tryStep。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await pumpSeconds(tester, 1.0);

    // 撤销：铃息与花瓣应回到走步前，HUD 收到一次快照变化。
    GamePage.debugHudBuildCount = 0;
    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(find.text('撤销'), findsOneWidget);
    expect(GamePage.debugHudBuildCount, greaterThan(0));

    // 两次满蓄力重叩入湾。
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

    await tester.tap(find.text('下一关'));
    await pumpSeconds(tester, 2.5);
    expect(find.text('第 2 关'), findsOneWidget);
    expect(find.text('听水'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
