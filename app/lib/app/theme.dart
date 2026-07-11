/// App theme: Material 3, seed-based color, refined surfaces, and typography.
/// Supports light + dark, plus optional platform dynamic color.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  /// Builds a theme for [brightness] from [seed], optionally using a
  /// platform-provided [dynamicScheme] (Android 12+/macOS accent).
  static ThemeData build({
    required Brightness brightness,
    required Color seed,
    ColorScheme? dynamicScheme,
  }) {
    final scheme = dynamicScheme ??
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    final baseText = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final textTheme = GoogleFonts.notoSansScTextTheme(baseText);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        elevation: 3,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        height: 68,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
    );
  }
}

/// Preset seed colors offered in Settings.
const List<Color> kSeedPresets = [
  Color(0xFF3B6FE0), // blue
  Color(0xFF2E7D5B), // NWAFU green
  Color(0xFF7A4FD0), // violet
  Color(0xFFD08A00), // amber
  Color(0xFFC0455B), // rose
  Color(0xFF00838F), // teal
];
