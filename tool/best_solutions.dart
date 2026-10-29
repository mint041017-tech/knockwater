// ignore_for_file: avoid_print
import 'dart:io';

import 'package:knockwater/game/levels.dart';

import 'canonical_solutions.dart';
import 'solver.dart';

String _token(String move) => const <String, String>{
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
}[move] ?? move;

void main() {
  final out = StringBuffer()
    ..writeln('# 铃渡 · 每关最佳解法')
    ..writeln()
    ..writeln('> 78 关最佳推荐解（按剩余铃息优先，其次动作数）。')
    ..writeln('> 每条均在 0.62s / 0.9s 双节奏下复验通过。')
    ..writeln();

  var count = 0;
  for (var i = 0; i < kLevels.length; i++) {
    final level = kLevels[i];
    String? bestEncoded;
    List<String> bestMoves = const <String>[];
    var bestRemaining = -1;
    for (final encoded in kCanonicalSolutions[i]) {
      final moves = encoded.split(' ');
      final slow = replaySolution(level, moves, 0.62);
      final fast = replaySolution(level, moves, 0.9);
      if (slow == null || fast == null) continue;
      final effective = effectiveMoves(level, moves, 0.62);
      if (effective.isEmpty) continue;
      final remaining = slow < fast ? slow : fast;
      if (remaining > bestRemaining ||
          (remaining == bestRemaining && effective.length < bestMoves.length)) {
        bestRemaining = remaining;
        bestMoves = effective;
        bestEncoded = encoded;
      }
    }
    if (bestEncoded == null) {
      print('L${i + 1} ${level.name}: NO VALID SOLUTION');
      continue;
    }
    count++;
    out
      ..writeln('## 第 ${i + 1} 关 · ${level.name}')
      ..writeln()
      ..writeln('`${level.chapter}` · 初始 ${level.charges} 铃息 · 余 $bestRemaining')
      ..writeln()
      ..writeln('`${bestMoves.map(_token).join(' ')}` — ${bestMoves.length} 动作')
      ..writeln();
  }
  out
    ..writeln('---')
    ..writeln()
    ..writeln('合计：$count 关');
  File('BEST_SOLUTIONS.md').writeAsStringSync(out.toString());
  print('BEST_SOLUTIONS.md written: $count levels');
  if (count != kLevels.length) exitCode = 1;
}
