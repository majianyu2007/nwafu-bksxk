/// Small shared UI building blocks used across pages.
library;

import 'package:flutter/material.dart';

/// A soft status pill.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
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
  });
  final int selected;
  final int capacity;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = capacity <= 0 ? 1.0 : (selected / capacity).clamp(0.0, 1.0);
    final remaining = capacity - selected;
    final full = remaining <= 0;
    final barColor = full
        ? scheme.error
        : remaining <= 3
            ? Colors.orange
            : scheme.primary;

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
          full ? '已满 $selected/$capacity' : '余 $remaining · $selected/$capacity',
          style: TextStyle(
            fontSize: 12,
            color: full ? scheme.error : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A centered empty-state with icon + message.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});
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
            Icon(icon, size: 56, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
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

/// Shows a floating snackbar with a success/error accent.
void showToast(BuildContext context, String message, {bool? success}) {
  final scheme = Theme.of(context).colorScheme;
  final color = success == null
      ? scheme.inverseSurface
      : success
          ? Colors.green.shade700
          : scheme.error;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 3),
    ));
}
