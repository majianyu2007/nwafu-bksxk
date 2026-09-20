import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/background.dart';

// Decode the public Pigeon toggle payload without importing a transitive package.
class _ToggleCodec extends StandardMessageCodec {
  const _ToggleCodec();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) => type == 129
      ? (readValue(buffer) as List).single
      : super.readValueOfType(type, buffer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a delayed keep-alive start cannot overtake a subsequent stop',
      () async {
    final started = Completer<void>();
    final releaseStart = Completer<void>();
    var enabled = false;
    const channel =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(channel, (message) async {
      final requested =
          (const _ToggleCodec().decodeMessage(message) as List).single as bool;
      if (requested) {
        started.complete();
        await releaseStart.future;
      }
      enabled = requested;
      return const StandardMessageCodec().encodeMessage([null]);
    });
    addTearDown(() => messenger.setMockMessageHandler(channel, null));
    final start = AppBackground.instance
        .setMonitoring(true, runInBackground: false, keepAwake: true);
    await started.future;
    final stop = AppBackground.instance
        .setMonitoring(false, runInBackground: false, keepAwake: true);
    await Future<void>.delayed(Duration.zero);
    releaseStart.complete();
    await Future.wait([start, stop]);
    expect(enabled, isFalse,
        reason: 'the last requested monitoring state wins');
  });
}
