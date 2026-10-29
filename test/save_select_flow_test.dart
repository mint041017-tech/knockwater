import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knockwater/game/progress.dart';
import 'package:knockwater/main.dart';

Future<void> pumpSeconds(WidgetTester tester, double seconds) async {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('选关锁定、入口与通关保存', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final progress = ProgressStore.memory();
    await tester.pumpWidget(KnockwaterApp(progress: progress));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('入 水'), findsOneWidget);
    await tester.tap(find.text('选 关').first);
    await tester.pump();

    // 第 2 关未解锁，点击不应进入。
    expect(progress.isUnlocked(1), isFalse);
    await tester.tap(find.text('听水'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('第 2 关'), findsNothing);

    // 点第 1 关进入。
    await tester.tap(find.text('初纹').last);
    await pumpSeconds(tester, 3.3);
    expect(find.text('第 1 关'), findsOneWidget);

    // 两次满蓄力重叩通关。
    for (var i = 0; i < 2; i++) {
      final center = tester.getCenter(find.text('重叩'));
      final gesture = await tester.startGesture(center);
      await pumpSeconds(tester, 1.4);
      await gesture.up();
      await pumpSeconds(tester, 4.2);
    }
    await pumpSeconds(tester, 3.0);

    expect(find.text('湾心已满'), findsOneWidget);
    expect(progress.isCompleted(0), isTrue);
    expect(progress.isUnlocked(1), isTrue);
    expect(progress.isUnlocked(2), isFalse);
    expect(progress.lastPlayed, 2);
    expect(progress.starsFor(0), greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('选关在宽屏 1200×800 无溢出', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final progress = ProgressStore.memory();
    await tester.pumpWidget(KnockwaterApp(progress: progress));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('选 关').first);
    await tester.pump();

    expect(find.text('初纹'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('继续会恢复局内稳定检查点', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final progress = ProgressStore.memory();
    await tester.pumpWidget(KnockwaterApp(progress: progress));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('入 水'));
    await pumpSeconds(tester, 3.2);

    final first = GamePage.debugEngine!;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await pumpSeconds(tester, 3.5);
    expect(progress.hasCheckpoint, isTrue);
    final cx = first.cellX;
    final cy = first.cellY;
    final charges = first.charges;

    // Force a fresh GamePage state so the title is shown again.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      KnockwaterApp(key: UniqueKey(), progress: progress),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('继 续'), findsOneWidget);
    await tester.tap(find.text('继 续'));
    await pumpSeconds(tester, 3.2);

    final restored = GamePage.debugEngine!;
    expect(restored.cellX, cx);
    expect(restored.cellY, cy);
    expect(restored.charges, charges);
    expect(tester.takeException(), isNull);
  });
}
