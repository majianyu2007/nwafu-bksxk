import 'dart:io';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/edu_providers.dart'
    show debugClockOffsetProvider, timetableProvider;
import 'app/providers.dart';
import 'app/theme.dart';
import 'app/ui_prefs.dart';
import 'data/background.dart';
import 'debug/live_probe.dart' as live_probe;
import 'data/notifications.dart';
import 'data/storage.dart';
import 'data/timetable_logic.dart';
import 'ui/root_shell.dart';

/// Debug builds expose the container to the VM service for live checks.
ProviderContainer? debugContainer;

/// Keeps the live probes linked into debug builds.
void debugProbeRecheck() => live_probe.probeRecheck(debugContainer!);
String debugProbeResult() => live_probe.probeResult;
void debugProbeBind() => live_probe.probeBind(
  debugContainer!,
  passwordPath: '${Directory.systemTemp.path}/pw',
  captchaPath: '${Directory.systemTemp.path}/captcha.png',
  deviceName: '西农教务助手 · Mac',
);
void debugProbeAnswer(String code) => live_probe.probeAnswerCaptcha(code);
void debugProbePasskeyLogin() => live_probe.probePasskeyLogin(debugContainer!);
void debugProbeSync() => live_probe.probeTimetableSync(debugContainer!);
void debugProbeCampus() => live_probe.probeCampus(debugContainer!);
void debugProbeDirect() => live_probe.probeDirect();
void debugProbeRooms() => live_probe.probeRoomsMeta(debugContainer!);
void debugProbeRoomsSample() => live_probe.probeRoomsSample(debugContainer!);
void debugFetch(String u) => live_probe.probeFetch(debugContainer!, u);
void debugRoomsTiming(int n) => live_probe.probeRoomsTiming(debugContainer!, n);
void debugTheme(bool dark) => debugContainer!
    .read(themeControllerProvider.notifier)
    .setMode(dark ? ThemeMode.dark : ThemeMode.light);
void debugShiftClock(int minutes) =>
    debugContainer!.read(debugClockOffsetProvider.notifier).state = Duration(
      minutes: minutes,
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  await AppBackground.instance.init();
  await NotificationService.instance.init();

  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
    ],
  );
  if (kDebugMode) debugContainer = container;
  // Pre-warm the ONNX captcha solver so the first captcha is recognised
  // without a cold-start pause. On the web the model is a 14 MB download, so
  // it starts after the first frame instead of competing with the app's own
  // scripts and fonts on a cold cache.
  if (kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => container.read(captchaSolverProvider).warmUp(),
    );
  } else {
    container.read(captchaSolverProvider).warmUp();
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const NwafuXkApp()),
  );
}

class NwafuXkApp extends ConsumerWidget {
  const NwafuXkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final textScale = ref.watch(textScaleProvider);
    final glass = ref.watch(glassEnabledProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: '西农教务助手',
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: AppTextScaler(media.textScaler, textScale),
              ),
              child: child!,
            );
          },
          themeMode: theme.mode,
          theme: AppTheme.build(
            brightness: Brightness.light,
            seed: theme.seed,
            dynamicScheme: theme.useDynamic ? lightDynamic?.harmonized() : null,
            glass: glass,
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            seed: theme.seed,
            dynamicScheme: theme.useDynamic ? darkDynamic?.harmonized() : null,
            glass: glass,
          ),
          // The offline timetable is available without a selection session.
          home: const RootShell(),
        );
      },
    );
  }
}

String debugDay(int y, int m, int d) => debugContainer!
    .read(timetableProvider)
    .data!
    .classesOn(DateTime.utc(y, m, d))
    .map(
      (o) =>
          '${o.session.courseName} ${o.session.startPeriod}-${o.session.endPeriod} ${o.session.room}',
    )
    .join('; ');
