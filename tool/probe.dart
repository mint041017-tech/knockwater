// ignore_for_file: avoid_print
import 'package:knockwater/game/engine.dart';

import 'canonical_solutions.dart';

const Map<String, List<int>> dirs = <String, List<int>>{
  'NW': <int>[-1, -1],
  'N': <int>[0, -1],
  'NE': <int>[1, -1],
  'W': <int>[-1, 0],
  'E': <int>[1, 0],
  'SW': <int>[-1, 1],
  'S': <int>[0, 1],
  'SE': <int>[1, 1],
};

void probe(int level, String seq, {double beat = 0.62}) {
  final e = Engine(level);
  print(
    'LEVEL ${level + 1} ${e.level.name} start bell=(${e.cellX},${e.cellY})',
  );
  for (final m in seq.split(' ')) {
    if (m.isEmpty) continue;
    if (m == 'K') {
      if (!e.startCharge()) {
        print('$m -> cannot charge');
        continue;
      }
      e.chargeT = 1.2;
      e.releaseCharge();
    } else if (m != '.') {
      final d = dirs[m];
      if (d == null) continue;
      final ok = e.step(d[0], d[1]);
      if (!ok) {
        print('$m -> BLOCKED at bell (${e.cellX},${e.cellY})');
        continue;
      }
    }
    e.advance(m == 'K' ? 1.4 : beat);
    final ps = e.petals
        .map(
          (p) =>
              '${p.x.toStringAsFixed(1)},${p.y.toStringAsFixed(1)}'
              '${p.inBay ? '*' : ''}${p.stranded ? '!' : ''}',
        )
        .join(' | ');
    print(
      '$m -> bell(${e.cellX},${e.cellY}) charges=${e.charges} '
      'petals=$ps status=${e.status.name}',
    );
    if (e.status != GameStatus.playing) break;
  }
  e.advance(2.6);
  final ps = e.petals
      .map(
        (p) =>
            '${p.x.toStringAsFixed(1)},${p.y.toStringAsFixed(1)}'
            '${p.inBay ? '*' : ''}${p.stranded ? '!' : ''}',
      )
      .join(' | ');
  print(
    'FINAL ${e.status.name} ${e.loseReason.name} charges=${e.charges} petals=$ps\n',
  );
}

void main(List<String> args) {
  final level = args.isEmpty ? 0 : (int.tryParse(args.first) ?? 1) - 1;
  final sequence = args.length > 1
      ? args[1]
      : kCanonicalSolutions[level.clamp(0, kCanonicalSolutions.length - 1)]
            .first;
  probe(level, sequence);
}
