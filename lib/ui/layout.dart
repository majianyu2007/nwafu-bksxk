/// Shared adaptive-layout helpers: Material 3 window size classes, the shell's
/// content width, and a Wrap-based grid whose rows follow content height.
///
/// Pages read the window class from the constraints the shell gives them (not
/// from MediaQuery), so the navigation rail's width is already accounted for.
library;

import 'package:flutter/material.dart';

/// Material 3 window size classes by available width.
enum WindowClass {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  static WindowClass of(double width) {
    if (width < 600) return WindowClass.compact;
    if (width < 840) return WindowClass.medium;
    if (width < 1200) return WindowClass.expanded;
    if (width < 1600) return WindowClass.large;
    return WindowClass.extraLarge;
  }

  /// Wide enough for side-by-side panes (rail layouts and up).
  bool get isWide => index >= WindowClass.expanded.index;
}

/// The shell switches from a bottom bar to a navigation rail at this width.
const double kRailBreakpoint = 840;

/// The rail shows labels beside icons from this width.
const double kExtendedRailBreakpoint = 1280;

/// Widest the shell lets page content grow; pages lay out columns inside it.
const double kContentMaxWidth = 1480;

/// A comfortable single-column reading width for settings-like pages.
const double kReadableMaxWidth = 860;

/// Horizontal page gutter for the given width.
double pageGutter(double width) => WindowClass.of(width).isWide ? 24 : 16;

/// Lays [children] out in as many equal-width columns as fit, given a minimum
/// column width. Rows take the height of their tallest child, so cards of
/// varying height still line up without a fixed aspect ratio.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minColumnWidth = 360,
    this.maxColumns = 4,
    this.spacing = 12,
    this.runSpacing = 12,
  });

  final List<Widget> children;
  final double minColumnWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;

  static int columnsFor(double width,
      {double minColumnWidth = 360, int maxColumns = 4, double spacing = 12}) {
    final fit = ((width + spacing) / (minColumnWidth + spacing)).floor();
    return fit.clamp(1, maxColumns);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = columnsFor(width,
            minColumnWidth: minColumnWidth,
            maxColumns: maxColumns,
            spacing: spacing);
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// A page title row shared by the tab pages: headline on the left, optional
/// actions on the right. Replaces per-page hand-rolled header rows so titles
/// align across tabs on every window size.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 8),
  });

  final String title;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Two side-by-side columns on wide layouts, stacked on narrow ones.
/// [primaryFlex] / [secondaryFlex] set the width ratio when side by side.
class TwoColumn extends StatelessWidget {
  const TwoColumn({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    this.gap = 16,
    this.breakpoint = 900,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;
  final double gap;

  /// Available width at which the columns go side by side.
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, SizedBox(height: gap), secondary],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: gap),
            Expanded(flex: secondaryFlex, child: secondary),
          ],
        );
      },
    );
  }
}

/// Shows [builder]'s content as a modal bottom sheet on phone-width windows
/// and as a centred dialog on wide ones, where a sheet stretched across a
/// desktop window is awkward to read and reach. Resolves with the value given
/// to Navigator.pop either way.
Future<T?> showAdaptiveSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = false,
  double maxWidth = 640,
  double heightFraction = 0.85,
}) {
  final size = MediaQuery.sizeOf(context);
  if (size.width < kRailBreakpoint) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: scrollControlled,
      showDragHandle: true,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * heightFraction,
        ),
        child: builder(context),
      ),
    ),
  );
}

/// True when [showAdaptiveSheet] would present a dialog for this context.
bool adaptiveSheetIsDialog(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kRailBreakpoint;
