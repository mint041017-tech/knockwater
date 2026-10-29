// ignore_for_file: avoid_print
import 'dart:io';

import 'package:knockwater/game/levels.dart';

import 'canonical_solutions.dart';
import 'solver.dart';

String _token(String move) {
  const map = <String, String>{
    'N': '↑',
    'S': '↓',
    'E': '→',
    'W': '←',
    'NE': '↗',
    'NW': '↖',
    'SE': '↘',
    'SW': '↙',
    'K': '重叩',
    '·': '停',
  };
  return map[move] ?? move;
}

void main() {
  if (kCanonicalSolutions.length != kLevels.length) {
    throw StateError(
      'Canonical solutions: ${kCanonicalSolutions.length}, '
      'levels: ${kLevels.length}',
    );
  }

  final markdown = StringBuffer()
    ..writeln('# 铃渡 · 全关推荐解')
    ..writeln()
    ..writeln('> 生成时间：${DateTime.now().toString().substring(0, 16)}')
    ..writeln('>')
    ..writeln('> 普通关卡保留恰好 3 条有效不同解；第七章每关唯一解。每条解都在 0.62 秒 / 0.9 秒两种操作间隔下复验通过。')
    ..writeln('>')
    ..writeln('> 动作集：八方向移动、满蓄力重叩（3 铃息）；`停` = 原地等待约 1 秒。')
    ..writeln()
    ..writeln('图例：↑上 ↓下 ←左 →右 ↖左上 ↗右上 ↙左下 ↘右下')
    ..writeln();

  var failures = 0;
  var total = 0;
  for (var i = 0; i < kLevels.length; i++) {
    final level = kLevels[i];
    final canonical = kCanonicalSolutions[i];
    final rows = <String>[];
    final distinct = <String>{};
    var bestCharges = 0;
    for (final encoded in canonical) {
      final moves = encoded.split(' ');
      final slow = replaySolution(level, moves, 0.62);
      final fast = replaySolution(level, moves, 0.9);
      if (slow == null || fast == null) {
        failures++;
        print('L${i + 1} ${level.name}: dual-beat failure [$encoded]');
        continue;
      }
      final effective = effectiveMoves(level, moves, 0.62);
      final key = effective.join(' ');
      if (effective.isEmpty || !distinct.add(key)) {
        failures++;
        print('L${i + 1} ${level.name}: duplicate/empty effective solution '
            '[$encoded]');
        continue;
      }
      final remaining = slow < fast ? slow : fast;
      if (bestCharges == 0 || remaining > bestCharges) bestCharges = remaining;
      rows.add(
        '`${effective.map(_token).join(' ')}` — '
        '${effective.where((m) => m != '·').length} 动作，余 $remaining 铃息',
      );
    }
    total += rows.length;
    final expected = level.chapter == '第七章 · 涡潮' ? 1 : 3;
    if (rows.length != expected) {
      failures++;
      print('L${i + 1} ${level.name}: expected $expected distinct, '
          'got ${rows.length}');
    }
    markdown
      ..writeln('## 第 ${i + 1} 关 · ${level.name}')
      ..writeln()
      ..writeln(
        '`${level.chapter}` · 初始 ${level.charges} 铃息 · '
        '收录 ${rows.length} 条',
      )
      ..writeln();
    for (var r = 0; r < rows.length; r++) {
      markdown.writeln('${r + 1}. ${rows[r]}');
    }
    if (rows.isNotEmpty) {
      markdown
        ..writeln()
        ..writeln('推荐解最佳剩余铃息：$bestCharges')
        ..writeln();
    }
  }

  markdown
    ..writeln('---')
    ..writeln()
    ..writeln('合计收录：$total 条；双节奏/去重失败：$failures 条。');
  File('SOLUTIONS.md').writeAsStringSync(markdown.toString());
  print('SOLUTIONS.md written: $total verified, $failures failed');
  if (failures > 0) exitCode = 1;
}
