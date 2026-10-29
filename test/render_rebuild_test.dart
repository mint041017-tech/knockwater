import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knockwater/game/painter.dart';
import 'package:knockwater/main.dart';

Future<void> pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> enterFirstLevel(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const KnockwaterApp());
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text('入 水'));
  await tester.pump();
  // 3.2s：跨过入场 (1.9s) 与提示浮现，之后保持静止水面。
  await pumpFrames(tester, 200);
}

void resetCounters() {
  GamePage.debugBuildCount = 0;
  GamePage.debugHudBuildCount = 0;
  PondPainter.debugPaintCount = 0;
}

void main() {
  testWidgets('空闲 1 秒：水面继续重绘，GamePage 与 HUD 都不重建', (tester) async {
    await enterFirstLevel(tester);
    resetCounters();
    await pumpFrames(tester, 60);
    expect(GamePage.debugBuildCount, 0, reason: '逐帧 Ticker 不应再触发整页 setState');
    expect(GamePage.debugHudBuildCount, 0, reason: 'HUD 快照未变化时不应重建');
    expect(PondPainter.debugPaintCount, greaterThan(0), reason: '水面必须继续按帧重绘');
    expect(tester.takeException(), isNull);
  });

  testWidgets('走步只更新 HUD 快照，不触发整页重建', (tester) async {
    await enterFirstLevel(tester);
    resetCounters();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      GamePage.debugHudBuildCount,
      greaterThan(0),
      reason: '铃息/可撤销变化应通知 HUD 子树',
    );
    expect(GamePage.debugBuildCount, 0);
    await pumpFrames(tester, 60);
    expect(GamePage.debugBuildCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重叩蓄力帧只重绘蓄力环，不重建 HUD 或页面', (tester) async {
    await enterFirstLevel(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('重叩')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    resetCounters();
    await pumpFrames(tester, 30);
    expect(GamePage.debugHudBuildCount, 0, reason: '蓄力比例是逐帧绘制值，不应进入 HUD 快照');
    expect(GamePage.debugBuildCount, 0);
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pump();
    expect(
      GamePage.debugHudBuildCount,
      greaterThan(0),
      reason: '松手释放后铃息变化应更新 HUD',
    );
  });

  testWidgets('宽屏 1200×800 入水后无溢出，HUD 正常出现', (tester) async {
    await enterFirstLevel(tester, size: const Size(1200, 800));
    expect(tester.takeException(), isNull);
    expect(find.text('第 1 关'), findsOneWidget);
    expect(find.text('重叩'), findsOneWidget);
  });
}
