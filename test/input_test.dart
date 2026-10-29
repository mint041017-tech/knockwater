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
  test('拖动方向解析：斜拖走斜向，浅斜拖回到主轴', () {
    expect(directionForDrag(const Offset(40, 8)), <int>[1, 0]);
    expect(directionForDrag(const Offset(-40, 8)), <int>[-1, 0]);
    expect(directionForDrag(const Offset(8, 40)), <int>[0, 1]);
    expect(directionForDrag(const Offset(8, -40)), <int>[0, -1]);
    expect(directionForDrag(const Offset(40, 40)), <int>[1, 1]);
    expect(directionForDrag(const Offset(-40, 40)), <int>[-1, 1]);
    expect(directionForDrag(const Offset(40, -40)), <int>[1, -1]);
    expect(directionForDrag(const Offset(-40, -40)), <int>[-1, -1]);
    expect(directionForDrag(const Offset(10, 10)), isNull);
  });

  testWidgets('真实拖动可以走出斜向一步', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const KnockwaterApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('入 水'));
    await pumpSeconds(tester, 3.2);

    final e = GamePage.debugEngine!;
    expect(find.text('教学 · 三步'), findsOneWidget);
    expect(e.cellX, 3);
    expect(e.cellY, 13);
    final charges = e.charges;

    final gesture = await tester.startGesture(const Offset(195, 430));
    await gesture.moveBy(const Offset(50, -50));
    await gesture.up();
    await tester.pump();

    expect(e.cellX, 4, reason: '斜向拖动应走 NE 一格');
    expect(e.cellY, 12, reason: '斜向拖动应走 NE 一格');
    expect(e.charges, charges - 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘 Q/E/C/V 可以走斜向', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const KnockwaterApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('入 水'));
    await pumpSeconds(tester, 3.2);

    final e = GamePage.debugEngine!;
    expect(e.cellX, 3);
    expect(e.cellY, 13);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(e.cellX, 2);
    expect(e.cellY, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘 W+A 组合走斜向', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const KnockwaterApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('入 水'));
    await pumpSeconds(tester, 3.2);

    final e = GamePage.debugEngine!;
    expect(e.cellX, 3);
    expect(e.cellY, 13);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.pump(const Duration(milliseconds: 60));
    expect(e.cellX, 2);
    expect(e.cellY, 12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
