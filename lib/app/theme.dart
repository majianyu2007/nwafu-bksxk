/// App theme: Material 3 from a seed colour, light + dark, optional platform
/// dynamic colour. Typography uses the bundled NotoSansSC subset so Chinese
/// renders identically everywhere and the app needs no font CDN.
library;

import 'package:flutter/material.dart';

/// Multiply the platform scaler without discarding its nonlinear behavior.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'NotoSansSC';

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
    final textTheme = baseText
        .apply(
          fontFamily: fontFamily,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          bodyLarge: baseText.bodyLarge?.copyWith(
              fontFamily: fontFamily, color: scheme.onSurface, height: 1.5),
          bodyMedium: baseText.bodyMedium?.copyWith(
              fontFamily: fontFamily, color: scheme.onSurface, height: 1.5),
          bodySmall: baseText.bodySmall?.copyWith(
              fontFamily: fontFamily,
              color: scheme.onSurfaceVariant,
              height: 1.4),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle:
            textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
    );
  }
}

/// Named seed colours offered in Settings; any other colour can be picked on
/// the hue wheel next to them.
const List<(String, Color)> kSeedPresets = [
  ('靛蓝', Color(0xFF3B6FE0)),
  ('西农绿', Color(0xFF2E7D5B)),
  ('青', Color(0xFF00838F)),
  ('天蓝', Color(0xFF1E88E5)),
  ('紫', Color(0xFF7A4FD0)),
  ('玫红', Color(0xFFC0455B)),
  ('橙', Color(0xFFE0641B)),
  ('琥珀', Color(0xFFD08A00)),
  ('橄榄', Color(0xFF6B8E23)),
  ('石墨', Color(0xFF546E7A)),
  ('棕', Color(0xFF795548)),
  ('黑', Color(0xFF212121)),
];
