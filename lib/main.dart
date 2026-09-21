import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/theme.dart';
import 'data/background.dart';
import 'data/notifications.dart';
import 'data/storage.dart';
import 'ui/login_page.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  await AppBackground.instance.init();
  await NotificationService.instance.init();

  final container = ProviderContainer(
    overrides: [storageProvider.overrideWithValue(storage)],
  );
  // Pre-warm the ONNX captcha solver so the first captcha is recognised
  // without a cold-start pause. On the web the model is a 14 MB download, so
  // it starts after the first frame instead of competing with the app's own
  // scripts and fonts on a cold cache.
  if (kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => container.read(captchaSolverProvider).warmUp());
  } else {
    container.read(captchaSolverProvider).warmUp();
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NwafuXkApp(),
    ),
  );
}

class NwafuXkApp extends ConsumerWidget {
  const NwafuXkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final signedIn = ref.watch(activeAccountIdProvider) != null;
    final textScale = ref.watch(textScaleProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: '西农本科选课',
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
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            seed: theme.seed,
            dynamicScheme: theme.useDynamic ? darkDynamic?.harmonized() : null,
          ),
          // The shell stays mounted while a shown account's session is
          // expired; it overlays the re-login dialog itself.
          home: signedIn ? const RootShell() : const LoginPage(),
        );
      },
    );
  }
}
