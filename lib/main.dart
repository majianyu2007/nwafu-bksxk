import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/theme.dart';
import 'data/notifications.dart';
import 'data/storage.dart';
import 'ui/login_page.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  await NotificationService.instance.init();

  // Build the ProviderContainer up front so we can pre-warm the ONNX captcha
  // solver before the login screen mounts. Cold-start model load otherwise
  // races the first captcha fetch and the user sees "no auto-recognize" even
  // though the toggle is on. Fire-and-forget: load continues in the background.
  final container = ProviderContainer(
    overrides: [storageProvider.overrideWithValue(storage)],
  );
  container.read(captchaSolverProvider).warmUp();

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
    final phase = ref.watch(sessionProvider.select((s) => s.phase));

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: '西农本科选课',
          debugShowCheckedModeBanner: false,
          themeMode: theme.mode,
          theme: AppTheme.build(
            brightness: Brightness.light,
            seed: theme.seed,
            dynamicScheme:
                theme.useDynamic ? lightDynamic?.harmonized() : null,
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            seed: theme.seed,
            dynamicScheme: theme.useDynamic ? darkDynamic?.harmonized() : null,
          ),
          // An expired session keeps the shell (and the user's place in it);
          // the shell overlays the re-login dialog.
          home: switch (phase) {
            AuthPhase.loggedIn || AuthPhase.expired => const RootShell(),
            AuthPhase.loggedOut || AuthPhase.loggingIn => const LoginPage(),
          },
        );
      },
    );
  }
}
