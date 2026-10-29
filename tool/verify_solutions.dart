// ignore_for_file: avoid_print
import 'dart:io';

import 'package:knockwater/game/levels.dart';

import 'canonical_solutions.dart';
import 'solver.dart';

void main() {
  if (kCanonicalSolutions.length != kLevels.length) {
    throw StateError(
      'Canonical solutions: ${kCanonicalSolutions.length}, '
      'levels: ${kLevels.length}',
    );
  }

  var entryFailures = 0;
  var structuralFailures = 0;
  var total = 0;
  for (var i = 0; i < kLevels.length; i++) {
    final level = kLevels[i];
    final canonical = kCanonicalSolutions[i];
    final expected = level.chapter == '第七章 · 涡潮' ? 1 : 3;
    if (canonical.length != expected) {
      structuralFailures++;
      print('L${i + 1} ${level.name}: expected $expected entries, '
          'got ${canonical.length}');
    }
    final distinct = <String>{};
    var passed = 0;
    for (final encoded in canonical) {
      final moves = encoded.split(' ');
      final results = <String>[];
      var ok = true;
      for (final beat in <double>[0.62, 0.9]) {
        final remaining = replaySolution(level, moves, beat);
        if (remaining == null) {
          ok = false;
          results.add('${beat}s:FAIL');
        } else {
          results.add('${beat}s:$remaining');
        }
      }
      final eff62 = effectiveMoves(level, moves, 0.62);
      final eff90 = effectiveMoves(level, moves, 0.9);
      if (eff62.isEmpty || eff90.isEmpty) ok = false;
      if (ok) distinct.add(eff62.join(' '));
      total++;
      if (ok) {
        passed++;
      } else {
        entryFailures++;
        print('L${i + 1} ${level.name}: ${results.join(' ')} [$encoded]');
      }
    }
    if (distinct.length != expected) {
      structuralFailures++;
      print('L${i + 1} ${level.name}: only ${distinct.length} distinct '
          'effective solutions (need $expected)');
    }
    print('L${i + 1} ${level.name}: $passed/${canonical.length} PASS, '
        '${distinct.length} distinct');
  }
  print(
    'Verified ${total - entryFailures}/$total canonical entries across '
    '${kLevels.length} levels; entryFailures=$entryFailures '
    'structuralFailures=$structuralFailures',
  );
  if (entryFailures > 0 || structuralFailures > 0) exitCode = 1;
}
