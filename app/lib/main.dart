import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/theme.dart';
import 'data/storage.dart';
import 'ui/login_page.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  runApp(
    ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage)],
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
          title: '西农抢课',
          debugShowCheckedModeBanner: false,
          themeMode: theme.mode,
          theme: AppTheme.build(
            brightness: Brightness.light,
            seed: theme.seed,
            dynamicScheme: lightDynamic?.harmonized(),
          ),
          darkTheme: AppTheme.build(
            brightness: Brightness.dark,
            seed: theme.seed,
            dynamicScheme: darkDynamic?.harmonized(),
          ),
          home: phase == AuthPhase.loggedIn ? const RootShell() : const LoginPage(),
        );
      },
    );
  }
}
