/// "Liquid glass" building blocks. Chrome ([GlassSurface], the capsule bar,
/// modal sheets) may blur what is behind it; content ([GlassCard]) is only
/// tinted so scrolling lists never pay for a live backdrop filter. Everything
/// turns solid when the 玻璃效果 setting is off (see [GlassTokens.enabled]).
library;

import 'dart:ui' as ui;

import 'package:fluid_glass/fluid_glass.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../layout.dart' show kRailBreakpoint;

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
    final fill = alpha == null ? t.chromeFill : t.fill(alpha!);
    final inner =
        padding == null ? child : Padding(padding: padding!, child: child);

    if (!t.enabled) {
      final scheme = Theme.of(context).colorScheme;
      final solidBorder = border
          ? Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
              width: 1,
            )
          : null;
      Widget surface = Material(
        color: fill,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: solidBorder == null
            ? inner
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: solidBorder,
                ),
                child: inner,
              ),
      );
      if (shadow) {
        surface = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: t.shadow,
          ),
          child: surface,
        );
      }
      return surface;
    }

    final apple = isApplePlatform(context);
    final uniform =
        borderRadius.topLeft == borderRadius.topRight &&
        borderRadius.topLeft == borderRadius.bottomLeft &&
        borderRadius.topLeft == borderRadius.bottomRight;
    final radius = borderRadius.topLeft.x;
    final shape = !uniform
        ? const RoundedRectangle(0)
        : radius >= 999
        ? const Capsule()
        : RoundedRectangle(radius);

    Widget panel = LiquidPanel(
      backdrop: nativeBackdrop,
      shape: shape,
      surfaceColor: apple ? fill.withValues(alpha: fill.a * 0.78) : fill,
      blurRadius: apple ? t.blurSigma * 1.4 : t.blurSigma,
      showHighlight: border,
      showShadow: shadow && uniform,
      child: inner,
    );
    if (!uniform) {
      panel = ClipRRect(borderRadius: borderRadius, child: panel);
    }
    return RepaintBoundary(child: panel);
  }
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
    final decoration = BoxDecoration(
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
    );
    Widget card = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: onTap == null && onLongPress == null
            ? Padding(padding: padding, child: child)
            : InkWell(
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
    final bottom = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
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
                              onTap: () {
                                if (!kIsWeb && i != selectedIndex) {
                                  final p = Theme.of(context).platform;
                                  if (p == TargetPlatform.iOS ||
                                      p == TargetPlatform.android) {
                                    HapticFeedback.selectionClick();
                                  }
                                }
                                onSelected(i);
                              },
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

/// A modal bottom sheet (phones) or dialog (wide) on a translucent glass
/// surface with radius 28.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 640,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final t = GlassTokens.of(context);
  if (width < kRailBreakpoint) {
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
    builder: (context) {
      final liveHeight = MediaQuery.sizeOf(context).height;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: liveHeight * 0.85,
          ),
          child: GlassSurface(
            alpha: t.sheetSurfaceAlpha,
            shadow: true,
            borderRadius: BorderRadius.circular(t.sheetRadius),
            child: builder(context),
          ),
        ),
      );
    },
  );
}
