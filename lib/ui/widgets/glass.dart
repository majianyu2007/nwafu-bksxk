/// "Liquid glass" building blocks. Chrome ([GlassSurface], the capsule bar,
/// modal sheets) may blur what is behind it; content ([GlassCard]) is only
/// tinted so scrolling lists never pay for a live backdrop filter. Everything
/// turns solid when the 玻璃效果 setting is off (see [GlassTokens.enabled]).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Whether animations should be skipped (system reduce-motion).
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A soft static background: a few large, blurred colour blobs from the theme
/// over the surface colour. Painted once (RepaintBoundary) and never
/// animated, so it costs nothing per frame.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: tokens.enabled
                ? _AuroraPainter(scheme.surface, tokens.auroraColors)
                : _SolidPainter(scheme.surface),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class _SolidPainter extends CustomPainter {
  const _SolidPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
  @override
  bool shouldRepaint(_SolidPainter old) => old.color != color;
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter(this.base, this.colors);
  final Color base;
  final List<Color> colors;

  // (centre x, centre y, radius) as fractions of the shorter side.
  static const _blobs = [
    (0.05, 0.02, 0.95),
    (0.98, 0.30, 0.8),
    (0.3, 1.0, 0.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final unit = size.shortestSide.clamp(320.0, 1400.0);
    for (var i = 0; i < colors.length && i < _blobs.length; i++) {
      final (x, y, r) = _blobs[i];
      final center = Offset(size.width * x, size.height * y);
      final radius = unit * r;
      // A radial gradient fading to transparent reads as a blurred blob
      // without a blur filter.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius,
            [
              colors[i],
              colors[i].withValues(alpha: colors[i].a * 0.45),
              colors[i].withValues(alpha: 0),
            ],
            const [0, 0.45, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.base != base ||
      old.colors.length != colors.length ||
      [
        for (var i = 0; i < colors.length; i++) old.colors[i] != colors[i],
      ].any((c) => c);
}

/// Translucent, blurred chrome (navigation, toolbars). Blurs only when glass
/// is enabled; otherwise a solid surface with the same shape.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.alpha,
    this.padding,
    this.shadow = false,
    this.border = true,
  });
  final Widget child;
  final BorderRadius borderRadius;

  /// Surface opacity; defaults to [GlassTokens.chromeFill].
  final double? alpha;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final apple = isApplePlatform(context);
    // Apple's materials blur harder and boost saturation, then lay a thin
    // bright rim on top; Material keeps the softer, flatter look.
    final fill = alpha == null ? t.chromeFill : t.fill(alpha!);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: apple && t.enabled
            ? fill.withValues(alpha: fill.a * 0.72)
            : fill,
        borderRadius: borderRadius,
        gradient: apple && t.enabled
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  t.highlight.withValues(alpha: t.sheenAlpha * 0.5),
                  fill.withValues(alpha: fill.a * 0.6),
                ],
                stops: const [0, 0.5],
              )
            : null,
        border: border && t.enabled
            ? Border.all(
                color: apple
                    ? t.highlight.withValues(alpha: t.borderAlpha * 2.2)
                    : t.border,
                width: apple ? 0.6 : 1,
              )
            : null,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (t.enabled) {
      final sigma = apple ? t.blurSigma * 2.6 : t.blurSigma;
      final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
      body = BackdropFilter(
        filter: apple
            ? ui.ImageFilter.compose(outer: _saturate, inner: blur)
            : blur,
        child: body,
      );
      body = apple
          ? ClipRSuperellipse(borderRadius: borderRadius, child: body)
          : ClipRRect(borderRadius: borderRadius, child: body);
    }
    if (!shadow) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: t.shadow,
      ),
      child: body,
    );
  }
}

/// Saturation boost of Apple's system materials (about 1.8×).
final _saturate = ui.ColorFilter.matrix(_saturation(1.8));

List<double> _saturation(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final i = 1 - s;
  return [
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0, //
    r * i, g * i, b * i + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// iOS and macOS get the Apple-material look.
bool isApplePlatform(BuildContext context) {
  final p = Theme.of(context).platform;
  return p == TargetPlatform.iOS || p == TargetPlatform.macOS;
}

/// Tinted translucent card for content. No blur. [tint] blends a colour into
/// the surface (e.g. the course colour); [sheen] adds a white highlight at
/// the top edge.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.tint,
    this.tintAmount = 0.12,
    this.radius,
    this.onTap,
    this.onLongPress,
    this.sheen = true,
    this.margin,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final double tintAmount;
  final double? radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool sheen;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final r = BorderRadius.circular(radius ?? t.cardRadius);
    var base = t.fill(t.cardSurfaceAlpha);
    if (tint != null) {
      base = Color.alphaBlend(tint!.withValues(alpha: tintAmount), base);
    }
    Widget card = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: base,
          borderRadius: r,
          border: Border.all(
            color: t.enabled
                ? t.border
                : Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          gradient: sheen && t.enabled ? sheenGradient(t, base) : null,
        ),
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (margin != null) card = Padding(padding: margin!, child: card);
    return card;
  }
}

/// The top-edge white sheen over [base].
LinearGradient sheenGradient(GlassTokens t, Color base) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color.alphaBlend(t.highlight.withValues(alpha: t.sheenAlpha), base),
    base,
  ],
  stops: const [0, 0.55],
);

class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

/// Floating capsule bottom bar: 64 dp tall, 16 dp side margins, a pill
/// indicator under the selected item. Labels are hidden for unselected items
/// on very narrow screens or large text.
class GlassCapsuleNavBar extends StatelessWidget {
  const GlassCapsuleNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<GlassNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final bottom = media.padding.bottom;
    final width = media.size.width;
    final scale = media.textScaler.scale(12) / 12;
    final tight = width < 360;
    final hideUnselectedLabels = width < 330 || scale > 1.45;
    final margin = tight ? 8.0 : t.navBarMargin;
    final height = t.navBarHeight + (scale > 1 ? ((scale - 1) * 18).clamp(0, 20) : 0);
    final duration = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        margin,
        0,
        margin,
        (bottom > 0 ? bottom : 0) + (tight ? 8 : 12),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassSurface(
            shadow: true,
            borderRadius: BorderRadius.circular(height / 2),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: EdgeInsets.all(tight ? 4 : 6),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: i == selectedIndex,
                          button: true,
                          label: items[i].label,
                          excludeSemantics: true,
                          child: Tooltip(
                            message: items[i].label,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(height / 2),
                              onTap: () => onSelected(i),
                              child: AnimatedContainer(
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                decoration: BoxDecoration(
                                  color: i == selectedIndex
                                      ? scheme.primary.withValues(alpha: 0.16)
                                      : Colors.transparent,
                                  borderRadius:
                                      BorderRadius.circular(height / 2),
                                ),
                                child: IconTheme.merge(
                                  data: IconThemeData(
                                    size: tight ? 20 : 22,
                                    color: i == selectedIndex
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      i == selectedIndex
                                          ? items[i].selectedIcon
                                          : items[i].icon,
                                      if (!hideUnselectedLabels ||
                                          i == selectedIndex) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          items[i].label,
                                          maxLines: 1,
                                          overflow: TextOverflow.fade,
                                          softWrap: false,
                                          style: TextStyle(
                                            fontSize: tight ? 10 : 11,
                                            height: 1.15,
                                            fontWeight: i == selectedIndex
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: i == selectedIndex
                                                ? scheme.primary
                                                : scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Height the floating bar occupies including its bottom gap, for content
/// that must scroll clear of it.
double glassNavBarExtent(BuildContext context) {
  final t = GlassTokens.of(context);
  final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
  return t.navBarHeight + (scale > 1 ? (scale - 1) * 16 : 0) + 12;
}

/// A modal bottom sheet (phones) or dialog (wide) on a translucent glass
/// surface with radius 28.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 640,
}) {
  final size = MediaQuery.sizeOf(context);
  final t = GlassTokens.of(context);
  if (size.width < 840) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) => GlassSurface(
        alpha: t.sheetSurfaceAlpha,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.sheetRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(child: builder(context)),
          ],
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * 0.85,
        ),
        child: GlassSurface(
          alpha: t.sheetSurfaceAlpha,
          shadow: true,
          borderRadius: BorderRadius.circular(t.sheetRadius),
          child: builder(context),
        ),
      ),
    ),
  );
}
