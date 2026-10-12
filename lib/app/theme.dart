/// App theme: Material 3 from a seed colour, light + dark, optional platform
/// dynamic colour. Typography uses the bundled NotoSansSC subset so Chinese
/// renders identically everywhere and the app needs no font CDN.
library;

import 'dart:ui' show lerpDouble;

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
    bool glass = true,
  }) {
    final scheme =
        dynamicScheme ??
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
            fontFamily: fontFamily,
            color: scheme.onSurface,
            height: 1.5,
          ),
          bodyMedium: baseText.bodyMedium?.copyWith(
            fontFamily: fontFamily,
            color: scheme.onSurface,
            height: 1.5,
          ),
          bodySmall: baseText.bodySmall?.copyWith(
            fontFamily: fontFamily,
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        );

    final tokens = brightness == Brightness.dark
        ? GlassTokens.dark(scheme, enabled: glass)
        : GlassTokens.light(scheme, enabled: glass);

    return ThemeData(
      useMaterial3: true,
      extensions: [tokens],
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
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: glass
            ? scheme.surfaceContainerLow.withValues(alpha: 0.72)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(glass ? 20 : 16),
          side: glass
              ? BorderSide(
                  color: Colors.white.withValues(
                    alpha: brightness == Brightness.dark ? 0.08 : 0.5,
                  ),
                )
              : BorderSide.none,
        ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
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

/// Design tokens for the translucent "liquid glass" look. Chrome (navigation,
/// sheets) may blur what is behind it; content (cards, course cells) is only
/// tinted, never live-blurred, so long lists stay cheap. With [enabled] off
/// every surface is solid and nothing blurs.
@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.enabled,
    required this.blurSigma,
    required this.navSurfaceAlpha,
    required this.chromeBaseAlpha,
    required this.borderAlpha,
    required this.shadowAlpha,
    required this.sheetSurfaceAlpha,
    required this.sheetRadius,
    required this.cardSurfaceAlpha,
    required this.cardRadius,
    required this.cellRadius,
    required this.cellTint,
    required this.cellTintNow,
    required this.sheenAlpha,
    required this.navBarHeight,
    required this.navBarMargin,
    required this.surface,
    required this.highlight,
    required this.auroraColors,
  });

  factory GlassTokens.light(ColorScheme s, {bool enabled = true}) =>
      GlassTokens(
        enabled: enabled,
        blurSigma: 10,
        navSurfaceAlpha: 0.16,
        chromeBaseAlpha: 0.62,
        borderAlpha: 0.14,
        shadowAlpha: 0.12,
        sheetSurfaceAlpha: 0.62,
        sheetRadius: 28,
        cardSurfaceAlpha: 0.66,
        cardRadius: 20,
        cellRadius: 12,
        cellTint: 0.14,
        cellTintNow: 0.24,
        sheenAlpha: 0.35,
        navBarHeight: 64,
        navBarMargin: 16,
        surface: s.surface,
        highlight: Colors.white,
        auroraColors: [
          s.primary.withValues(alpha: 0.22),
          s.tertiary.withValues(alpha: 0.18),
          s.secondary.withValues(alpha: 0.16),
        ],
      );

  factory GlassTokens.dark(ColorScheme s, {bool enabled = true}) => GlassTokens(
    enabled: enabled,
    blurSigma: 10,
    navSurfaceAlpha: 0.10,
    chromeBaseAlpha: 0.58,
    borderAlpha: 0.14,
    shadowAlpha: 0.12,
    sheetSurfaceAlpha: 0.62,
    sheetRadius: 28,
    cardSurfaceAlpha: 0.55,
    cardRadius: 20,
    cellRadius: 12,
    cellTint: 0.14,
    cellTintNow: 0.24,
    sheenAlpha: 0.08,
    navBarHeight: 64,
    navBarMargin: 16,
    surface: s.surfaceContainerLow,
    highlight: Colors.white,
    auroraColors: [
      s.primary.withValues(alpha: 0.20),
      s.tertiary.withValues(alpha: 0.14),
      s.secondary.withValues(alpha: 0.12),
    ],
  );

  final bool enabled;

  /// Backdrop blur of navigation chrome (sigma).
  final double blurSigma;

  /// White glass layer over navigation chrome.
  final double navSurfaceAlpha;

  /// Opacity of the surface colour under that layer, so labels stay legible
  /// over whatever scrolls behind.
  final double chromeBaseAlpha;
  final double borderAlpha;
  final double shadowAlpha;
  final double sheetSurfaceAlpha;
  final double sheetRadius;
  final double cardSurfaceAlpha;
  final double cardRadius;
  final double cellRadius;

  /// How much of the course colour a timetable cell takes (now = the class
  /// in progress).
  final double cellTint;
  final double cellTintNow;

  /// Opacity of the white sheen at the top of tinted surfaces.
  final double sheenAlpha;
  final double navBarHeight;
  final double navBarMargin;

  /// The base colour translucent surfaces are made of.
  final Color surface;
  final Color highlight;
  final List<Color> auroraColors;

  static GlassTokens of(BuildContext context) =>
      Theme.of(context).extension<GlassTokens>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? GlassTokens.dark(Theme.of(context).colorScheme)
          : GlassTokens.light(Theme.of(context).colorScheme));

  /// Fill for a surface with [alpha] translucency, solid when disabled.
  Color fill(double alpha) =>
      enabled ? surface.withValues(alpha: alpha) : surface;

  /// Navigation chrome fill: translucent surface plus a light glass layer.
  Color get chromeFill => enabled
      ? Color.alphaBlend(
          highlight.withValues(alpha: navSurfaceAlpha),
          surface.withValues(alpha: chromeBaseAlpha),
        )
      : surface;

  Color get border => highlight.withValues(alpha: enabled ? borderAlpha : 0);

  List<BoxShadow> get shadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: shadowAlpha),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  @override
  GlassTokens copyWith({bool? enabled}) => GlassTokens(
    enabled: enabled ?? this.enabled,
    blurSigma: blurSigma,
    navSurfaceAlpha: navSurfaceAlpha,
    chromeBaseAlpha: chromeBaseAlpha,
    borderAlpha: borderAlpha,
    shadowAlpha: shadowAlpha,
    sheetSurfaceAlpha: sheetSurfaceAlpha,
    sheetRadius: sheetRadius,
    cardSurfaceAlpha: cardSurfaceAlpha,
    cardRadius: cardRadius,
    cellRadius: cellRadius,
    cellTint: cellTint,
    cellTintNow: cellTintNow,
    sheenAlpha: sheenAlpha,
    navBarHeight: navBarHeight,
    navBarMargin: navBarMargin,
    surface: surface,
    highlight: highlight,
    auroraColors: auroraColors,
  );

  @override
  GlassTokens lerp(GlassTokens? other, double t) {
    if (other == null) return this;
    double l(double a, double b) => lerpDouble(a, b, t)!;
    return GlassTokens(
      enabled: t < 0.5 ? enabled : other.enabled,
      blurSigma: l(blurSigma, other.blurSigma),
      navSurfaceAlpha: l(navSurfaceAlpha, other.navSurfaceAlpha),
      chromeBaseAlpha: l(chromeBaseAlpha, other.chromeBaseAlpha),
      borderAlpha: l(borderAlpha, other.borderAlpha),
      shadowAlpha: l(shadowAlpha, other.shadowAlpha),
      sheetSurfaceAlpha: l(sheetSurfaceAlpha, other.sheetSurfaceAlpha),
      sheetRadius: l(sheetRadius, other.sheetRadius),
      cardSurfaceAlpha: l(cardSurfaceAlpha, other.cardSurfaceAlpha),
      cardRadius: l(cardRadius, other.cardRadius),
      cellRadius: l(cellRadius, other.cellRadius),
      cellTint: l(cellTint, other.cellTint),
      cellTintNow: l(cellTintNow, other.cellTintNow),
      sheenAlpha: l(sheenAlpha, other.sheenAlpha),
      navBarHeight: l(navBarHeight, other.navBarHeight),
      navBarMargin: l(navBarMargin, other.navBarMargin),
      surface: Color.lerp(surface, other.surface, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      auroraColors: [
        for (var i = 0; i < auroraColors.length; i++)
          Color.lerp(
            auroraColors[i],
            i < other.auroraColors.length ? other.auroraColors[i] : null,
            t,
          )!,
      ],
    );
  }
}

/// Ten course colours, distinguishable in light and dark, used as tints and
/// accent bars. A course keeps its colour across weeks and syncs because the
/// index is derived from its code (see [courseColorFor]).
const List<Color> kCoursePalette = [
  Color(0xFF3B82F6), // blue
  Color(0xFF10B981), // emerald
  Color(0xFFF59E0B), // amber
  Color(0xFFEF4444), // red
  Color(0xFF8B5CF6), // violet
  Color(0xFF06B6D4), // cyan
  Color(0xFFEC4899), // pink
  Color(0xFF84CC16), // lime
  Color(0xFFF97316), // orange
  Color(0xFF6366F1), // indigo
];

/// Stable palette colour for [key] (FNV-1a, so it does not depend on Dart's
/// per-run string hash).
Color courseColorFor(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return kCoursePalette[hash % kCoursePalette.length];
}
