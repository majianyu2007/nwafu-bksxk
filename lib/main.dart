import 'dart:async' show unawaited;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/edu_providers.dart'
    show debugClockOffsetProvider, timetableProvider;
import 'app/providers.dart';
import 'app/theme.dart';
import 'app/ui_prefs.dart';
import 'data/background.dart';
import 'debug/live_probe_stub.dart'
    if (dart.library.io) 'debug/live_probe.dart'
    as live_probe;
import 'data/notifications.dart';
import 'data/storage.dart';
import 'data/timetable_logic.dart';
import 'ui/layout.dart';
import 'ui/root_shell.dart';

/// Debug builds expose the container to the VM service for live checks.
ProviderContainer? debugContainer;

/// Keeps the live probes linked into debug builds.
void debugProbeRecheck() => live_probe.probeRecheck(debugContainer!);
String debugProbeResult() => live_probe.probeResult;
void debugProbeBind() => live_probe.probeBindDefault(debugContainer!);
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
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('Uncaught platform error: $error\n$stack');
    }
    return true;
  };

  final prefs = await SharedPreferences.getInstance();
  final storage = Storage(prefs);
  try {
    await AppBackground.instance.init();
  } catch (e) {
    if (kDebugMode) debugPrint('AppBackground init skipped: $e');
  }
  try {
    await NotificationService.instance.init();
  } catch (e) {
    if (kDebugMode) debugPrint('NotificationService init skipped: $e');
  }
  if (!kIsWeb) {
    unawaited(FluidGlass.ensureInitialized().catchError((Object _) {}));
  }

  final container = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  if (kDebugMode) debugContainer = container;
  // Pre-warm the ONNX captcha solver after the first frame so cold start stays
  // snappy on every platform (on Web it is also a 14 MB download).
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => container.read(captchaSolverProvider).warmUp(),
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const NwafuXkApp()),
  );
}

class NwafuXkApp extends ConsumerWidget {
  const NwafuXkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final glass = ref.watch(glassEnabledProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: '西农教务助手',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => _AdaptiveShellBuilder(child: child!),
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

/// Applies adaptive scaling + text scale inside [MaterialApp.builder] without
/// rebuilding [MaterialApp] or both [ThemeData] objects when scale settings
/// change.
class _AdaptiveShellBuilder extends ConsumerWidget {
  const _AdaptiveShellBuilder({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScale = ref.watch(textScaleProvider);
    final scaleMode = ref.watch(uiScaleModeProvider);
    final media = MediaQuery.of(context);
    final systemScale = media.textScaler.scale(14) / 14;
    final adaptive = computeAdaptiveScale(
      media.size,
      scaleMode,
      systemScale: systemScale,
    );
    final currentTheme = Theme.of(context);
    final scaledMedia = media.copyWith(
      textScaler: AppTextScaler(
        media.textScaler,
        textScale * adaptive.factor,
      ),
    );
    return MediaQuery(
      data: scaledMedia,
      child: Theme(
        data: currentTheme.visualDensity == adaptive.density
            ? currentTheme
            : currentTheme.copyWith(visualDensity: adaptive.density),
        child: child,
      ),
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
void debugProbeLibrary() => live_probe.probeLibrary(debugContainer!);
void debugProbeAcademic() => live_probe.probeAcademic(debugContainer!);
