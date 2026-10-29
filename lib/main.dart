import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'game/engine.dart';
import 'game/hud_snapshot.dart';
import 'game/levels.dart';
import 'game/painter.dart';
import 'game/progress.dart';
import 'game/sfx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final progress = await ProgressStore.load(totalLevels: kLevels.length);
  runApp(KnockwaterApp(progress: progress));
}

const TextStyle _serif = TextStyle(
  fontFamily: 'Songti SC',
  fontFamilyFallback: <String>[
    'STSong',
    'SimSun',
    'Noto Serif CJK SC',
    'Noto Serif SC',
    'serif',
  ],
);

const Color _paper = Color(0xFFF2E9D8);
const Color _jadeText = Color(0xFFA9F5E6);
const Color _gold = Color(0xFFE3B878);
const Color _coral = Color(0xFFFF9E7A);

/// Maps a drag delta to one of the eight engine directions.
///
/// A mostly diagonal drag produces a diagonal step; shallow diagonal drags
/// fall back to the dominant axis so ordinary horizontal/vertical swipes stay
/// easy to trigger.
List<int>? directionForDrag(
  Offset delta, {
  double threshold = 38,
  double diagonalRatio = 0.45,
}) {
  if (delta.distance < threshold) return null;
  final adx = delta.dx.abs();
  final ady = delta.dy.abs();
  if (adx == 0 && ady == 0) return null;
  final sx = delta.dx.sign.toInt();
  final sy = delta.dy.sign.toInt();
  if (adx > 0 && ady > 0) {
    final ratio = math.min(adx, ady) / math.max(adx, ady);
    if (ratio >= diagonalRatio) return <int>[sx, sy];
  }
  if (adx >= ady) return <int>[sx, 0];
  return <int>[0, sy];
}

class KnockwaterApp extends StatelessWidget {
  const KnockwaterApp({super.key, this.progress});

  final ProgressStore? progress;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '铃渡',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF030A0B),
        fontFamily: 'PingFang SC',
        fontFamilyFallback: const <String>[
          'Hiragino Sans GB',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'sans-serif',
        ],
      ),
      home: GamePage(progress: progress),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key, this.progress});

  final ProgressStore? progress;

  /// 测试专用：页面级 build 次数（仅在 debug / 测试中累加）。
  static int debugBuildCount = 0;

  /// 测试专用：HUD 快照子树的 build 次数（仅在 debug / 测试中累加）。
  static int debugHudBuildCount = 0;

  /// 测试专用：最近一次挂载的引擎，用于验证真实输入落点。
  static Engine? debugEngine;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final FocusNode _focus;
  late final ValueNotifier<int> _frame;
  late final ValueNotifier<GameHudSnapshot> _hud;
  late Engine _engine;
  late ProgressStore _progress;

  int _level = 0;
  bool _showTitle = true;
  bool _showEnd = false;
  bool _showSelect = false;
  bool _progressSaved = false;
  double _lastCheckpointAt = -1;
  String? _lastCheckpointJson;
  bool _hintVisible = false;
  String? _toast;
  double _shakeUntil = 0;
  bool _knockHeld = false;
  bool _introVisible = false;
  bool _coachVisible = false;
  bool _hasKnocked = false;
  bool _soundOn = true;
  int? _bufferDx;
  int? _bufferDy;
  double _bufferAt = 0;
  final Set<LogicalKeyboardKey> _heldDirections = <LogicalKeyboardKey>{};
  Timer? _keyStepTimer;
  List<int>? _pendingKeyDir;
  bool _keyStepPending = false;

  Timer? _hintTimer;
  Timer? _toastTimer;
  Timer? _introTimer;
  Timer? _coachTimer;
  Duration _lastElapsed = Duration.zero;
  Offset? _dragLast;

  @override
  void initState() {
    super.initState();
    _progress = widget.progress ?? ProgressStore.memory();
    _engine = Engine(0);
    GamePage.debugEngine = _engine;
    _frame = ValueNotifier<int>(0);
    _focus = FocusNode(debugLabel: 'pond');
    _soundOn = !Sfx.muted;
    _bindAudio(_engine);
    final bootLevel = int.tryParse(Uri.base.queryParameters['level'] ?? '');
    if (bootLevel != null) {
      final index = (bootLevel - 1).clamp(0, kLevels.length - 1).toInt();
      // Direct links are a development convenience; in a release build they
      // must not skip the sequential unlock gate.
      if (_progress.isUnlocked(index) || kDebugMode) {
        _level = index;
        _engine = Engine(_level);
        GamePage.debugEngine = _engine;
        _bindAudio(_engine);
        _showTitle = false;
        _introVisible = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _schedulePresentation();
        });
      }
    }
    _hud = ValueNotifier<GameHudSnapshot>(GameHudSnapshot.of(_engine));
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _frame.dispose();
    _hud.dispose();
    _hintTimer?.cancel();
    _toastTimer?.cancel();
    _introTimer?.cancel();
    _coachTimer?.cancel();
    _keyStepTimer?.cancel();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    _engine.update(dt.clamp(0.0, 0.05).toDouble());
    if (_bufferDx != null && !_engine.moving) {
      final dx = _bufferDx!;
      final dy = _bufferDy!;
      _bufferDx = null;
      _bufferDy = null;
      if (_engine.status == GameStatus.playing &&
          _engine.charges > 0 &&
          _engine.time - _bufferAt < 0.7) {
        _tryStep(dx, dy, buffered: true);
      }
    }
    _frame.value++;
    _syncHud();
    if (_engine.status != GameStatus.playing && !_progressSaved) {
      _progressSaved = true;
      if (_engine.status == GameStatus.won) {
        unawaited(
          _progress.complete(
            _level,
            _engine.stars,
            totalLevels: kLevels.length,
          ),
        );
      } else {
        unawaited(_progress.clearCheckpoint());
      }
    }
    if (_engine.status == GameStatus.playing &&
        !_showTitle &&
        !_showEnd &&
        !_showSelect &&
        !_engine.moving &&
        !_engine.charging &&
        _engine.waves.isEmpty &&
        _engine.pending.isEmpty &&
        _engine.petals.every((p) => !p.stranded) &&
        _engine.time - _lastCheckpointAt >= 0.8) {
      _lastCheckpointAt = _engine.time;
      final raw = _checkpointJson();
      if (raw != _lastCheckpointJson) {
        _lastCheckpointJson = raw;
        unawaited(_progress.saveCheckpoint(raw));
      }
    }
    if (!_showTitle &&
        !_showEnd &&
        _engine.status != GameStatus.playing &&
        _engine.endDelay <= 0) {
      setState(() {
        _showEnd = true;
        _introVisible = false;
        _hintVisible = false;
        _coachVisible = false;
        _bufferDx = null;
        _bufferDy = null;
      });
    }
  }

  void _syncHud() {
    final next = GameHudSnapshot.of(_engine);
    if (next != _hud.value) _hud.value = next;
  }

  void _startLevel(int index, {bool resume = false}) {
    if (index < 0 || index >= kLevels.length) return;
    if (!_progress.isUnlocked(index)) return;
    _introTimer?.cancel();
    _hintTimer?.cancel();
    _coachTimer?.cancel();
    _clearKeyboardStep();
    Sfx.init();
    Sfx.ui();
    final restored = resume ? _restoreCheckpoint(index) : null;
    final next = restored ?? Engine(index);
    if (restored == null) unawaited(_progress.clearCheckpoint());
    _bindAudio(next);
    _progressSaved = false;
    _lastCheckpointAt = -1;
    _lastCheckpointJson = null;
    setState(() {
      _level = index;
      _engine = next;
      GamePage.debugEngine = _engine;
      _showTitle = false;
      _showEnd = false;
      _showSelect = false;
      _introVisible = true;
      _hintVisible = false;
      _coachVisible = false;
      _toast = null;
      _shakeUntil = 0;
      _bufferDx = null;
      _bufferDy = null;
    });
    unawaited(_progress.markPlayed(index, totalLevels: kLevels.length));
    _focus.requestFocus();
    _syncHud();
    _schedulePresentation();
  }

  Engine? _restoreCheckpoint(int index) {
    final raw = _progress.checkpoint;
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return null;
      if ((data['v'] as num?)?.toInt() != 1) return null;
      if ((data['level'] as num?)?.toInt() != index + 1) return null;
      final petalsData = data['petals'];
      if (petalsData is! List) return null;
      final e = Engine(index);
      if (petalsData.length != e.petals.length) return null;
      final cx = (data['cellX'] as num?)?.toInt();
      final cy = (data['cellY'] as num?)?.toInt();
      if (cx == null || cy == null) return null;
      if (cx < 0 || cx >= kCols || cy < 0 || cy >= kRows) return null;
      final charges = (data['charges'] as num?)?.toInt();
      if (charges == null || charges < 0 || charges > e.maxCharges) {
        return null;
      }
      e.charges = charges;
      e.cellX = cx;
      e.cellY = cy;
      e.bx = cx + 0.5;
      e.by = cy + 0.5;
      e.fromX = e.bx;
      e.fromY = e.by;
      e.toX = e.bx;
      e.toY = e.by;
      e.moving = false;
      e.moveT = 0;
      e.charging = false;
      e.chargeT = 0;
      e.steps = (data['steps'] as num?)?.toInt() ?? 0;
      e.status = GameStatus.playing;
      e.loseReason = LoseReason.none;
      e.winTimer = 0;
      e.loseTimer = 0;
      e.idleTimer = 0;
      e.endDelay = 0;
      e.wonAt = -1;
      e.shake = 0;
      e.bayFlash = 0;
      e.time = 0;
      e.waves.clear();
      e.pending.clear();
      e.sparks.clear();
      for (var i = 0; i < e.petals.length; i++) {
        final p = data['petals'][i];
        if (p is! Map<String, dynamic>) return null;
        final petal = e.petals[i];
        petal.x = (p['x'] as num).toDouble();
        petal.y = (p['y'] as num).toDouble();
        petal.vx = (p['vx'] as num?)?.toDouble() ?? 0;
        petal.vy = (p['vy'] as num?)?.toDouble() ?? 0;
        petal.spin = (p['spin'] as num?)?.toDouble() ?? 0;
        petal.stranded = p['stranded'] == true;
        petal.settled = p['settled'] == true;
        petal.bayTime = (p['bayTime'] as num?)?.toDouble() ?? 0;
        if (petal.stranded) return null;
        final dx = petal.x - e.bay.x;
        final dy = petal.y - e.bay.y;
        petal.inBay = dx * dx + dy * dy <
            (e.bay.r - 0.05) * (e.bay.r - 0.05);
      }
      return e;
    } catch (_) {
      return null;
    }
  }

  String _checkpointJson() {
    return jsonEncode(<String, Object?>{
      'v': 1,
      'level': _level + 1,
      'charges': _engine.charges,
      'cellX': _engine.cellX,
      'cellY': _engine.cellY,
      'steps': _engine.steps,
      'petals': <Map<String, Object?>>[
        for (final p in _engine.petals)
          <String, Object?>{
            'x': p.x,
            'y': p.y,
            'vx': p.vx,
            'vy': p.vy,
            'spin': p.spin,
            'stranded': p.stranded,
            'settled': p.settled,
            'bayTime': p.bayTime,
          },
      ],
    });
  }

  void _openSelect() {
    if (_showSelect) return;
    Sfx.ui();
    setState(() => _showSelect = true);
  }

  void _closeSelect() {
    if (!_showSelect) return;
    Sfx.ui();
    setState(() => _showSelect = false);
  }

  void _bindAudio(Engine e) {
    e.onSettle = () => _safeSfx(Sfx.settle);
    e.onStrand = () => _safeSfx(Sfx.strand);
    e.onWin = () => _safeSfx(Sfx.win);
    e.onLose = () => _safeSfx(Sfx.lose);
  }

  void _safeSfx(void Function() fn) {
    try {
      fn();
    } catch (_) {}
  }

  void _toggleSound() {
    setState(() => _soundOn = !_soundOn);
    Sfx.setMuted(!_soundOn);
    Sfx.init();
    if (_soundOn) Sfx.ui();
  }

  void _schedulePresentation() {
    _introTimer?.cancel();
    _hintTimer?.cancel();
    _introTimer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted || _showTitle || _showEnd) return;
      setState(() {
        _introVisible = false;
        _hintVisible = true;
      });
      _hintTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        setState(() => _hintVisible = false);
      });
      _maybeShowCoach();
    });
  }

  void _skipIntro() {
    if (!_introVisible) return;
    _introTimer?.cancel();
    setState(() {
      _introVisible = false;
      _hintVisible = true;
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _hintVisible = false);
    });
    _maybeShowCoach();
  }

  void _maybeShowCoach() {
    if (_hasKnocked || _coachVisible || _showTitle || _showEnd) return;
    if (!_engine.level.allowHeavy) return;
    if (_introVisible) return;
    if (_engine.charges < 3) return;
    if (_engine.levelIndex == 0 && _engine.steps < 4) return;
    setState(() => _coachVisible = true);
    _coachTimer?.cancel();
    _coachTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => _coachVisible = false);
    });
  }

  void _restart() {
    _startLevel(_level);
    HapticFeedback.selectionClick();
  }

  void _nextLevel() {
    if (_level + 1 < kLevels.length) {
      _startLevel(_level + 1);
    } else {
      _startLevel(0);
    }
  }

  void _undo() {
    if (_engine.undo()) {
      _bufferDx = null;
      _bufferDy = null;
      _progressSaved = false;
      _lastCheckpointAt = -1;
      _lastCheckpointJson = null;
      Sfx.ui();
      setState(() => _showEnd = false);
      _syncHud();
      HapticFeedback.selectionClick();
    }
  }

  bool _tryStep(int dx, int dy, {bool buffered = false}) {
    if (dx == 0 && dy == 0) return false;
    if (_showTitle || _showEnd) return false;
    final e = _engine;
    if (e.moving && !buffered && e.charges > 0) {
      _bufferDx = dx;
      _bufferDy = dy;
      _bufferAt = e.time;
      return true;
    }
    final ok = e.step(dx, dy);
    if (!ok) {
      if (e.charges <= 0 && !e.moving && !e.charging) {
        _showToast('铃息用尽了');
      }
      return false;
    }
    _bufferDx = null;
    _bufferDy = null;
    if (_introVisible) _skipIntro();
    HapticFeedback.selectionClick();
    Sfx.step(e.steps);
    if (e.steps >= 2 && _hintVisible) {
      _hintTimer?.cancel();
      setState(() => _hintVisible = false);
    }
    if (e.levelIndex == 0 && e.steps >= 4) _maybeShowCoach();
    _syncHud();
    return true;
  }

  void _onKnockStart() {
    if (_showTitle || _showEnd) return;
    if (!_engine.level.allowHeavy) {
      _showToast('静水章：重叩失效，只能走步');
      return;
    }
    if (_engine.startCharge()) {
      _knockHeld = true;
      _hasKnocked = true;
      _coachTimer?.cancel();
      _bufferDx = null;
      _bufferDy = null;
      Sfx.init();
      Sfx.charge();
      if (_coachVisible) setState(() => _coachVisible = false);
      if (_introVisible) _skipIntro();
      _syncHud();
      HapticFeedback.selectionClick();
      return;
    }
    if (_engine.charges < 3 && !_engine.moving) {
      _showToast('重叩需要 3 点铃息');
      setState(() => _shakeUntil = _engine.time + 0.36);
    }
  }

  void _onKnockEnd() {
    _knockHeld = false;
    Sfx.chargeStop();
    final p = _engine.releaseCharge();
    _syncHud();
    if (p != null) {
      HapticFeedback.mediumImpact();
      Sfx.knock(p);
    }
  }

  void _onKnockCancel() {
    _knockHeld = false;
    Sfx.chargeStop();
    _engine.cancelCharge();
    _syncHud();
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      setState(() => _toast = null);
    });
  }

  bool _isDirectionKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.keyS;
  }

  List<int>? _directionFromHeld() {
    var dx = 0;
    var dy = 0;
    if (_heldDirections.contains(LogicalKeyboardKey.arrowLeft) ||
        _heldDirections.contains(LogicalKeyboardKey.keyA)) {
      dx -= 1;
    }
    if (_heldDirections.contains(LogicalKeyboardKey.arrowRight) ||
        _heldDirections.contains(LogicalKeyboardKey.keyD)) {
      dx += 1;
    }
    if (_heldDirections.contains(LogicalKeyboardKey.arrowUp) ||
        _heldDirections.contains(LogicalKeyboardKey.keyW)) {
      dy -= 1;
    }
    if (_heldDirections.contains(LogicalKeyboardKey.arrowDown) ||
        _heldDirections.contains(LogicalKeyboardKey.keyS)) {
      dy += 1;
    }
    if (dx == 0 && dy == 0) return null;
    return <int>[dx, dy];
  }

  void _onDirectionKeyDown(LogicalKeyboardKey key) {
    _heldDirections.add(key);
    _pendingKeyDir = _directionFromHeld();
    _keyStepPending = true;
    _keyStepTimer?.cancel();
    // A short window lets W+A / ↑+← become one diagonal step instead of two
    // cardinal steps. A lone key still moves after this window.
    _keyStepTimer = Timer(const Duration(milliseconds: 45), _flushKeyboardStep);
  }

  void _onDirectionKeyUp(LogicalKeyboardKey key) {
    _heldDirections.remove(key);
    if (_heldDirections.isEmpty && !_keyStepPending) {
      _keyStepTimer?.cancel();
      _keyStepTimer = null;
    }
  }

  void _flushKeyboardStep() {
    _keyStepTimer = null;
    final direction = _directionFromHeld() ?? _pendingKeyDir;
    _pendingKeyDir = null;
    _keyStepPending = false;
    if (direction == null) return;
    _tryStep(direction[0], direction[1]);
    if (_heldDirections.isNotEmpty) {
      _keyStepTimer = Timer(
        const Duration(milliseconds: 140),
        _flushKeyboardStep,
      );
    }
  }

  void _clearKeyboardStep() {
    _heldDirections.clear();
    _pendingKeyDir = null;
    _keyStepPending = false;
    _keyStepTimer?.cancel();
    _keyStepTimer = null;
  }

  void _handleKey(KeyEvent event) {
    if (_showTitle) return;
    final key = event.logicalKey;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_isDirectionKey(key)) {
        _onDirectionKeyDown(key);
      } else if (key == LogicalKeyboardKey.space && event is KeyDownEvent) {
        _onKnockStart();
      } else if (key == LogicalKeyboardKey.keyZ && event is KeyDownEvent) {
        _undo();
      } else if (key == LogicalKeyboardKey.keyR && event is KeyDownEvent) {
        _restart();
      } else if (key == LogicalKeyboardKey.keyQ) {
        _tryStep(-1, -1);
      } else if (key == LogicalKeyboardKey.keyE) {
        _tryStep(1, -1);
      } else if (key == LogicalKeyboardKey.keyC) {
        _tryStep(-1, 1);
      } else if (key == LogicalKeyboardKey.keyV) {
        _tryStep(1, 1);
      }
    } else if (event is KeyUpEvent) {
      if (_isDirectionKey(key)) {
        _onDirectionKeyUp(key);
      } else if (key == LogicalKeyboardKey.space && _knockHeld) {
        _onKnockEnd();
      }
    }
  }

  void _handlePanStart(DragStartDetails d) {
    if (_showTitle || _showEnd) return;
    Sfx.init();
    _focus.requestFocus();
    _dragLast = d.localPosition;
  }

  void _handlePanUpdate(DragUpdateDetails d) {
    if (_showTitle || _showEnd) return;
    final last = _dragLast;
    if (last == null) return;
    final v = d.localPosition - last;
    final dir = directionForDrag(v);
    if (dir == null) return;
    final adx = v.dx.abs();
    final ady = v.dy.abs();
    final sx = v.dx.sign.toInt();
    final sy = v.dy.sign.toInt();
    var ok = _tryStep(dir[0], dir[1]);
    if (!ok) {
      // If a clear diagonal step is blocked, keep the old dominant-axis
      // fallback so a roughly horizontal/vertical swipe still feels lenient.
      if (adx >= ady) {
        ok = _tryStep(sx, 0) || (sy != 0 && _tryStep(0, sy));
      } else {
        ok = _tryStep(0, sy) || (sx != 0 && _tryStep(sx, 0));
      }
    }
    if (ok) {
      _dragLast = d.localPosition;
    }
  }

  void _handlePanEnd(DragEndDetails d) {
    _dragLast = null;
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      GamePage.debugBuildCount++;
      return true;
    }());
    final mq = MediaQuery.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            decoration: const BoxDecoration(
              boxShadow: <BoxShadow>[
                BoxShadow(color: Color(0xCC000000), blurRadius: 60),
              ],
            ),
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final top = 108.0 + mq.padding.top;
                  final bottom = 136.0 + mq.padding.bottom;
                  final rawH = constraints.maxHeight - top - bottom;
                  final availH = math.max(200.0, rawH);
                  final rect = Rect.fromLTWH(
                    10,
                    top + (rawH - availH) / 2,
                    constraints.maxWidth - 20,
                    availH,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      const RepaintBoundary(
                        child: CustomPaint(painter: BackdropPainter()),
                      ),
                      Positioned.fill(
                        child: KeyboardListener(
                          focusNode: _focus,
                          autofocus: true,
                          onKeyEvent: _handleKey,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: _handlePanStart,
                            onPanUpdate: _handlePanUpdate,
                            onPanEnd: _handlePanEnd,
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: PondPainter(
                                  engine: _engine,
                                  playRect: rect,
                                  showGame: !_showTitle,
                                  repaint: _frame,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 150,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Color(0xCC030A0B),
                                  Color(0x00030A0B),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 250,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Color(0x00030A0B),
                                  Color(0xF2030A0B),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      ValueListenableBuilder<GameHudSnapshot>(
                        valueListenable: _hud,
                        builder: (context, hud, _) => _buildHud(context, hud),
                      ),
                      _buildIntro(context),
                      _buildTitle(context),
                      if (_showEnd) _buildEnd(context),
                      _buildToast(),
                      if (_showSelect) _buildLevelSelect(context),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tutorialTip() {
    final moved = _engine.steps > 0;
    final knocked = _hasKnocked;
    final banked = _engine.petalsInBay > 0;
    final done = (moved ? 1 : 0) + (knocked ? 1 : 0) + (banked ? 1 : 0);
    Widget row(String text, bool ok) {
      return Row(
        children: <Widget>[
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 12,
            color: ok ? _jadeText : _paper.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                letterSpacing: 0.2,
                color: _paper.withValues(alpha: ok ? 0.82 : 0.6),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '教学 · 三步',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: _gold.withValues(alpha: 0.8),
              ),
            ),
            const Spacer(),
            Text(
              '$done/3',
              style: TextStyle(
                fontSize: 10,
                color: _jadeText.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        row('拖动水面，走一步', moved),
        row('按住重叩，蓄满松手', knocked),
        row('让花瓣落进湾心', banked),
      ],
    );
  }

  Widget _buildHud(BuildContext context, GameHudSnapshot hud) {
    assert(() {
      GamePage.debugHudBuildCount++;
      return true;
    }());
    final chromeHidden = _showTitle || _showEnd || _introVisible;
    return RepaintBoundary(
      child: IgnorePointer(
        ignoring: chromeHidden,
        child: AnimatedOpacity(
          opacity: chromeHidden ? 0 : 1,
          duration: const Duration(milliseconds: 400),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Text(
                            '第 ${hud.levelIndex + 1} 关',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2.4,
                              color: _jadeText.withValues(alpha: 0.42),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            hud.levelName,
                            style: _serif.copyWith(
                              fontSize: 21,
                              letterSpacing: 6,
                              color: _paper.withValues(alpha: 0.94),
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            '花瓣',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.6,
                              color: _jadeText.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${hud.petalsInBay}/${hud.petalCount}',
                            style: const TextStyle(
                              fontSize: 13,
                              letterSpacing: 1.6,
                              color: _coral,
                              fontFeatures: <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _toggleSound,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF07181A)
                                    .withValues(alpha: 0.55),
                                border: Border.all(
                                  color: _jadeText.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Icon(
                                _soundOn
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_off_rounded,
                                size: 16,
                                color: _jadeText.withValues(
                                  alpha: _soundOn ? 0.7 : 0.3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '铃息',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: _jadeText.withValues(alpha: 0.38),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: <Widget>[
                            for (var i = 0; i < hud.maxCharges; i++)
                              _ChargeDot(filled: i < hud.charges),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _hintVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 600),
                    child: IgnorePointer(
                      child: SizedBox(
                        width: math.min(
                          340,
                          MediaQuery.sizeOf(context).width * 0.86,
                        ),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 9, 16, 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF051214)
                                .withValues(alpha: 0.74),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _paper.withValues(alpha: 0.09),
                            ),
                          ),
                          child: _level == 0
                              ? _tutorialTip()
                              : Row(
                                  children: <Widget>[
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _gold,
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: _gold.withValues(alpha: 0.7),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        kLevels[hud.levelIndex].hint,
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.65,
                                          letterSpacing: 0.3,
                                          color: _paper.withValues(
                                            alpha: 0.76,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      _CircleButton(
                        label: '撤销',
                        dim: !hud.canUndo,
                        onTap: _undo,
                      ),
                      const SizedBox(width: 9),
                      _CircleButton(label: '重开', onTap: _restart),
                      const SizedBox(width: 9),
                      _CircleButton(label: '选关', onTap: _openSelect),
                      const Spacer(),
                      _ShakeOnFrame(
                        frames: _frame,
                        engine: _engine,
                        shakeUntil: _shakeUntil,
                        child: _buildKnockButton(hud),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKnockButton(GameHudSnapshot hud) {
    final e = _engine;
    final charging = hud.charging;
    final available = hud.knockAvailable && _engine.level.allowHeavy;
    final coach = _coachVisible && !charging;
    final content = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(
          painter: _KnockRingPainter(engine: e, repaint: _frame),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '重叩',
                style: _serif.copyWith(
                  fontSize: 17,
                  letterSpacing: 3,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                coach ? '按住蓄力' : '3',
                style: TextStyle(
                  fontSize: coach ? 8.5 : 9,
                  letterSpacing: 0.6,
                  color: _gold.withValues(alpha: coach ? 0.8 : 0.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    Widget shell;
    if (coach) {
      shell = AnimatedBuilder(
        animation: _frame,
        child: content,
        builder: (context, child) {
          final pulse = 0.5 + 0.5 * math.sin(e.time * 4);
          return _knockShell(
            charging: charging,
            coach: true,
            coachPulse: pulse,
            child: child!,
          );
        },
      );
    } else {
      shell = _knockShell(
        charging: charging,
        coach: false,
        coachPulse: 0,
        child: content,
      );
    }

    return Listener(
      onPointerDown: (_) => _onKnockStart(),
      onPointerUp: (_) => _onKnockEnd(),
      onPointerCancel: (_) => _onKnockCancel(),
      child: AnimatedOpacity(
        opacity: available ? 1 : 0.38,
        duration: const Duration(milliseconds: 250),
        child: AnimatedScale(
          scale: charging ? 1.045 : 1,
          duration: const Duration(milliseconds: 180),
          child: shell,
        ),
      ),
    );
  }

  Widget _knockShell({
    required bool charging,
    required bool coach,
    required double coachPulse,
    required Widget child,
  }) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(0, -0.15),
          colors: <Color>[Color(0xFF33594F), Color(0xFF081A1C)],
          stops: <double>[0, 0.72],
        ),
        border: Border.all(
          color: _gold.withValues(
            alpha: charging ? 0.8 : (coach ? 0.48 + 0.22 * coachPulse : 0.36),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _gold.withValues(
              alpha: charging ? 0.22 : (coach ? 0.08 + 0.1 * coachPulse : 0.07),
            ),
            blurRadius: charging ? 34 : (coach ? 26 : 18),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildIntro(BuildContext context) {
    final level = _engine.level;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _introVisible ? 1 : 0,
          duration: const Duration(milliseconds: 520),
          child: Align(
            alignment: const Alignment(0, -0.38),
            child: TweenAnimationBuilder<double>(
              key: ValueKey<int>(_level),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) {
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 18,
                ),
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.85,
                    colors: <Color>[Color(0x73030A0B), Color(0x00030A0B)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      level.chapter,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 4,
                        color: _gold.withValues(alpha: 0.65),
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      level.name,
                      style: _serif.copyWith(
                        fontSize: 34,
                        letterSpacing: 10,
                        color: _paper.withValues(alpha: 0.96),
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 22,
                          ),
                          Shadow(
                            color: _jadeText.withValues(alpha: 0.18),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    Container(
                      width: 30,
                      height: 1,
                      color: _gold.withValues(alpha: 0.45),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      level.blurb,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.75,
                        letterSpacing: 0.8,
                        color: _paper.withValues(alpha: 0.66),
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final hasProgress = _progress.completedCount > 0 ||
        _progress.highestUnlocked > 1 ||
        _progress.hasCheckpoint;
    var resumeIndex = (_progress.lastPlayed - 1)
        .clamp(0, kLevels.length - 1)
        .toInt();
    if (!_progress.isUnlocked(resumeIndex)) {
      resumeIndex = (_progress.highestUnlocked - 1)
          .clamp(0, kLevels.length - 1)
          .toInt();
    }
    return IgnorePointer(
      ignoring: !_showTitle,
      child: AnimatedOpacity(
        opacity: _showTitle ? 1 : 0,
        duration: const Duration(milliseconds: 650),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xCC030B0C),
                Color(0x30030B0C),
                Color(0xE0030B0C),
              ],
              stops: <double>[0, 0.38, 1],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: _gold.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '铃',
                      style: _serif.copyWith(fontSize: 20, color: _gold),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '铃渡',
                    style: _serif.copyWith(
                      fontSize: 60,
                      height: 1.1,
                      letterSpacing: 20,
                      color: _paper.withValues(alpha: 0.97),
                      shadows: <Shadow>[
                        Shadow(
                          color: _jadeText.withValues(alpha: 0.28),
                          blurRadius: 46,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '一 步 一 纹',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 7,
                      color: _jadeText.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    '你走过的路，就是你的手。',
                    style: _serif.copyWith(
                      fontSize: 14,
                      letterSpacing: 1.8,
                      color: _paper.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 36),
                  _PrimaryButton(
                    label: hasProgress ? '继 续' : '入 水',
                    onTap: () => _startLevel(
                      hasProgress ? resumeIndex : 0,
                      resume: _progress.hasCheckpoint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _openSelect,
                    style: TextButton.styleFrom(
                      foregroundColor: _jadeText,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      '选 关',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 6,
                        color: _jadeText.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  if (hasProgress) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      '已通关 ${_progress.completedCount}/${kLevels.length} · '
                      '已解锁 ${_progress.highestUnlocked}/${kLevels.length}',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: _paper.withValues(alpha: 0.38),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    '拖动水面行走 · 每一步荡开一圈铃波\n把花瓣推回湾心，别让它搁浅',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 2,
                      letterSpacing: 1,
                      color: _paper.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnd(BuildContext context) {
    final e = _engine;
    final won = e.status == GameStatus.won;
    final finalLevel = won && _level == kLevels.length - 1;
    final title = won
        ? (finalLevel ? '全池已醒' : '湾心已满')
        : (e.loseReason == LoseReason.stranded ? '花瓣搁浅' : '铃息已尽');
    final text = won
        ? (finalLevel
              ? '水记住了你的脚步。\n湾心重新亮起来，池水开始唱歌。'
              : '还剩 ${e.charges} 点铃息。\n水面安静下来，听它慢慢合上。')
        : (e.loseReason == LoseReason.stranded
              ? '它留在了浅滩上。\n再轻一点，或者换一条路。'
              : '水面安静下来，还有花瓣没有回到湾心。');

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          color: const Color(0xFF030B0C).withValues(alpha: 0.62),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) {
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 14 * (1 - t)),
                  child: child,
                ),
              );
            },
            child: Container(
              width: 330,
              padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xF20C2223), Color(0xF7051012)],
                ),
                border: Border.all(color: _gold.withValues(alpha: 0.24)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x99000000), blurRadius: 60),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    won ? '第 ${_level + 1} 关 · 完成' : '水 面',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 4,
                      color: _gold.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: _serif.copyWith(
                      fontSize: 28,
                      letterSpacing: 5,
                      color: _paper.withValues(alpha: 0.96),
                    ),
                  ),
                  if (won) ...<Widget>[
                    const SizedBox(height: 18),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOut,
                      builder: (context, t, _) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            for (var i = 0; i < 3; i++)
                              Opacity(
                                opacity: t,
                                child: Transform.scale(
                                  scale:
                                      0.45 +
                                      0.55 *
                                          Curves.easeOutBack.transform(
                                            ((t * 1.7) - i * 0.35).clamp(
                                              0.0,
                                              1.0,
                                            ),
                                          ),
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i < e.stars
                                          ? _gold
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: _gold.withValues(
                                          alpha: i < e.stars ? 1 : 0.3,
                                        ),
                                      ),
                                      boxShadow: i < e.stars
                                          ? <BoxShadow>[
                                              BoxShadow(
                                                color: _gold.withValues(
                                                  alpha: 0.5,
                                                ),
                                                blurRadius: 10,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.9,
                      letterSpacing: 0.4,
                      color: _paper.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (won) ...<Widget>[
                    _ActionButton(
                      label: finalLevel ? '回到第一关' : '下一关',
                      primary: true,
                      onTap: _nextLevel,
                    ),
                    const SizedBox(height: 9),
                  ] else if (e.canUndo) ...<Widget>[
                    _ActionButton(label: '回溯一步', primary: true, onTap: _undo),
                    const SizedBox(height: 9),
                  ],
                  _ActionButton(
                    label: won ? '再走一次' : '重开',
                    primary: !won && !e.canUndo,
                    onTap: _restart,
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _openSelect,
                    style: TextButton.styleFrom(
                      foregroundColor: _jadeText,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: Text(
                      '选 关',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 3,
                        color: _jadeText.withValues(alpha: 0.68),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLevelSelect(BuildContext context) {
    final byChapter = <String, List<int>>{};
    for (var i = 0; i < kLevels.length; i++) {
      byChapter.putIfAbsent(kLevels[i].chapter, () => <int>[]).add(i);
    }
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xF7030B0C),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 18, 4),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: _closeSelect,
                      icon: const Icon(Icons.close_rounded),
                      color: _paper.withValues(alpha: 0.75),
                      tooltip: '关闭',
                    ),
                    Text(
                      '选 关',
                      style: _serif.copyWith(
                        fontSize: 24,
                        letterSpacing: 6,
                        color: _paper.withValues(alpha: 0.96),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '已通关 ${_progress.completedCount}/${kLevels.length}',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: _gold.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  children: <Widget>[
                    for (final entry in byChapter.entries) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 2.4,
                              color: _gold.withValues(alpha: 0.72),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${entry.value.where(_progress.isCompleted).length}'
                            '/${entry.value.length}',
                            style: TextStyle(
                              fontSize: 10,
                              color: _paper.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const gap = 8.0;
                          final width = (constraints.maxWidth - gap * 3) / 4;
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: <Widget>[
                              for (final i in entry.value)
                                SizedBox(width: width, child: _levelTile(i)),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _levelTile(int index) {
    final unlocked = _progress.isUnlocked(index);
    final completed = _progress.isCompleted(index);
    final stars = _progress.starsFor(index);
    final current = index == _level;
    final border = current
        ? _gold.withValues(alpha: 0.75)
        : completed
        ? _jadeText.withValues(alpha: 0.42)
        : _paper.withValues(alpha: 0.12);
    return IgnorePointer(
      ignoring: !unlocked,
      child: GestureDetector(
        onTap: unlocked ? () => _startLevel(index) : null,
        child: Opacity(
          opacity: unlocked ? 1 : 0.42,
          child: Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: unlocked
                  ? const Color(0xCC0A1D1F)
                  : const Color(0x99071113),
              border: Border.all(color: border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: unlocked
                        ? _gold.withValues(alpha: 0.82)
                        : _paper.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kLevels[index].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: _paper.withValues(alpha: unlocked ? 0.82 : 0.45),
                  ),
                ),
                const SizedBox(height: 2),
                if (!unlocked)
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 11,
                    color: _paper.withValues(alpha: 0.34),
                  )
                else if (completed)
                  Text(
                    stars > 0
                        ? List<String>.filled(stars, '★').join()
                        : '✓',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1,
                      color: _gold.withValues(alpha: 0.8),
                    ),
                  )
                else
                  const SizedBox(height: 9),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToast() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 124,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _toast == null ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF051012).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: _paper.withValues(alpha: 0.1)),
              ),
              child: Text(
                _toast ?? '',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: _paper.withValues(alpha: 0.66),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShakeOnFrame extends StatefulWidget {
  final Listenable frames;
  final Engine engine;
  final double shakeUntil;
  final Widget child;
  const _ShakeOnFrame({
    required this.frames,
    required this.engine,
    required this.shakeUntil,
    required this.child,
  });

  @override
  State<_ShakeOnFrame> createState() => _ShakeOnFrameState();
}

/// 只在“铃息不足”的 0.36s 内监听逐帧值。
/// 空闲时不订阅 Ticker，也不重建/重绘按钮子树。
class _ShakeOnFrameState extends State<_ShakeOnFrame> {
  double _dx = 0;
  bool _listening = false;

  double get _shakeOffset {
    final t = (widget.shakeUntil - widget.engine.time)
        .clamp(0.0, 0.36)
        .toDouble();
    if (t <= 0) return 0;
    return math.sin(widget.engine.time * 72) * 5 * (t / 0.36);
  }

  @override
  void initState() {
    super.initState();
    _syncListener();
  }

  @override
  void didUpdateWidget(covariant _ShakeOnFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames != widget.frames && _listening) {
      oldWidget.frames.removeListener(_onFrame);
      _listening = false;
    }
    _syncListener();
  }

  void _syncListener() {
    final active = widget.shakeUntil > widget.engine.time;
    if (active) {
      if (!_listening) {
        widget.frames.addListener(_onFrame);
        _listening = true;
      }
      _dx = _shakeOffset;
    } else {
      _stop();
      _dx = 0;
    }
  }

  void _onFrame() {
    final next = _shakeOffset;
    if (next == 0) _stop();
    if (next != _dx) setState(() => _dx = next);
  }

  void _stop() {
    if (_listening) {
      widget.frames.removeListener(_onFrame);
      _listening = false;
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dx == 0) return widget.child;
    return Transform.translate(offset: Offset(_dx, 0), child: widget.child);
  }
}

class _ChargeDot extends StatelessWidget {
  final bool filled;
  const _ChargeDot({required this.filled});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: filled ? 6 : 5,
      height: filled ? 6 : 5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? _gold.withValues(alpha: 0.86) : Colors.transparent,
        border: filled
            ? null
            : Border.all(color: _gold.withValues(alpha: 0.22)),
        boxShadow: filled
            ? <BoxShadow>[
                BoxShadow(color: _gold.withValues(alpha: 0.45), blurRadius: 7),
              ]
            : null,
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool dim;
  const _CircleButton({
    required this.label,
    required this.onTap,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: dim ? 0.32 : 1,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF07181A).withValues(alpha: 0.62),
            border: Border.all(color: _gold.withValues(alpha: 0.28)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              color: _paper.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xA62E524A), Color(0xCC0C2222)],
          ),
          border: Border.all(color: _gold.withValues(alpha: 0.55)),
          boxShadow: <BoxShadow>[
            BoxShadow(color: _gold.withValues(alpha: 0.1), blurRadius: 34),
          ],
        ),
        child: Text(
          label,
          style: _serif.copyWith(
            fontSize: 15,
            letterSpacing: 8,
            color: const Color(0xFFF6ECD9),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: primary
              ? const LinearGradient(
                  colors: <Color>[Color(0x8C34584F), Color(0xBF0C2222)],
                )
              : null,
          color: primary ? null : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: primary
                ? _gold.withValues(alpha: 0.5)
                : _paper.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 2.6,
            color: primary
                ? const Color(0xFFF6ECD9)
                : _paper.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}

class _KnockRingPainter extends CustomPainter {
  final Engine engine;
  _KnockRingPainter({required this.engine, required Listenable repaint})
    : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final progress = engine.charging ? engine.chargeRatio : 0.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _gold.withValues(alpha: 0.16);
    canvas.drawCircle(center, radius, base);
    if (progress <= 0.001) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD08A).withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFD79A).withValues(alpha: 0.9);
    final sweep = progress * math.pi * 2;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glow);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _KnockRingPainter oldDelegate) =>
      oldDelegate.engine != engine;
}
