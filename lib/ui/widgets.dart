/// Small shared UI building blocks used across pages.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/errors.dart';
import '../data/course_service.dart';
import '../data/info_service.dart';
import '../data/models.dart';
import 'widgets/glass.dart';

/// A soft status pill.
class StatusPill extends StatelessWidget {
  const StatusPill(
      {super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A capacity meter: filled bar with selected/total and remaining emphasis.
class CapacityBar extends StatelessWidget {
  const CapacityBar({
    super.key,
    required this.selected,
    required this.capacity,
    this.height = 6,
    this.known = true,
    this.label,
  });
  final int selected;
  final int capacity;
  final double height;

  /// Optional prefix naming what [selected] counts (e.g. 第一志愿).
  final String? label;

  /// False when the server gave no figures (whole-school query rows), so the
  /// bar must not read as "full".
  final bool known;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!known) {
      return Text(
        '余量以所属类别页面为准',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }
    final ratio = capacity <= 0 ? 1.0 : (selected / capacity).clamp(0.0, 1.0);
    final remaining = capacity - selected;
    final full = remaining <= 0;
    final oversubscribed = capacity > 0 && selected > capacity;
    final oddsPct = oversubscribed
        ? ((capacity / selected) * 100).round().clamp(1, 99)
        : null;
    final barColor = oversubscribed
        ? (oddsPct! < 35 ? scheme.error : Colors.deepOrange)
        : full
            ? scheme.error
            : remaining <= 3
                ? Colors.orange
                : scheme.primary;
    final summaryText = oversubscribed
        ? '约 $oddsPct% 中签  $selected/$capacity'
        : full
            ? '已满 $selected/$capacity'
            : '余 $remaining  $selected/$capacity';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: height,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${label == null ? '' : '$label '}$summaryText',
          style: TextStyle(
            fontSize: 12,
            color: full ? barColor : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A centered empty-state with icon + message.
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: TextStyle(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A one-line notice strip (warning / info) used above lists.
class NoticeStrip extends StatelessWidget {
  const NoticeStrip({
    super.key,
    required this.text,
    required this.icon,
    this.error = false,
    this.action,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  });
  final String text;
  final IconData icon;
  final bool error;
  final Widget? action;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = error ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final fg = error ? scheme.onErrorContainer : scheme.onSurface;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final message = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: fg)),
            ),
          ],
        );
        if (action == null) return message;
        if (constraints.maxWidth < 480 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              message,
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: action),
            ],
          );
        }
        return Row(children: [
          Expanded(child: message),
          const SizedBox(width: 12),
          action!,
        ]);
      }),
    );
  }
}

/// A key/value row for detail sheets.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, maxWidth: 112),
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ),
          Expanded(
              child:
                  SelectableText(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

/// Formats credits without trailing `.0` (e.g. `2.0` -> `2`, `2.5` -> `2.5`).
String formatCredit(double credit) =>
    credit == credit.roundToDouble()
        ? credit.toStringAsFixed(0)
        : credit.toStringAsFixed(1);

/// Fetches textbook options for a teaching class annotated with decline reasons.
Future<List<TextbookOption>> fetchAnnotatedTextbookOptions({
  required CourseService course,
  required InfoService info,
  required String studentCode,
  required String batchCode,
  required String teachingClassId,
}) async {
  final results = await Future.wait([
    course.fetchTextbookOptions(
      studentCode: studentCode,
      batchCode: batchCode,
      teachingClassId: teachingClassId,
    ),
    info.fetchTextbookReasons(),
  ]);
  final reasons = results[1] as List<TextbookReason>;
  return [
    for (final o in results[0] as List<TextbookOption>)
      o.copyWith(reasonCodes: reasons),
  ];
}

/// Centered GlassCard empty / sign-in prompt shared by academic pages.
class ActionEmptyCard extends StatelessWidget {
  const ActionEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 18),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Error card for unified-identity / ehall / portal pages, offering re-login
/// when the error is [AppErrorKind.sessionExpired] and retry otherwise.
class EduErrorCard extends StatelessWidget {
  const EduErrorCard({
    super.key,
    required this.error,
    required this.onRetry,
    this.onRelogin,
    this.fallbackMessage = '加载失败，请稍后重试',
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onRelogin;
  final String fallbackMessage;

  @override
  Widget build(BuildContext context) {
    final appError = error is AppError ? error as AppError : null;
    final expired = appError?.kind == AppErrorKind.sessionExpired;
    final msg = appError?.message ?? fallbackMessage;
    final hint = appError?.hint;
    return ActionEmptyCard(
      icon: expired ? Icons.lock_clock_outlined : Icons.cloud_off_outlined,
      title: msg,
      subtitle: hint,
      actionLabel: expired && onRelogin != null ? '重新登录' : '重试',
      onAction: expired && onRelogin != null ? onRelogin : onRetry,
    );
  }
}

/// Shows a floating snackbar with a success/error accent.
void showToast(BuildContext context, String message, {bool? success}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  final (bg, fg) = switch (success) {
    null => (scheme.inverseSurface, scheme.onInverseSurface),
    true => (Colors.green.shade700, Colors.white),
    false => (scheme.error, scheme.onError),
  };
  final availWidth = MediaQuery.sizeOf(context).width - 32;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: fg)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        width: availWidth > 80 ? math.min(560, availWidth) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
}

/// "HH:mm:ss".
String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
