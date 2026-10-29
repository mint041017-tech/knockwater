import 'dart:async';

import 'package:knockwater/game/sfx.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Audio is a platform plugin; widget tests use fake time and should not wait
  // for asset loading or audio player futures.
  Sfx.testMode = true;
  await testMain();
}
