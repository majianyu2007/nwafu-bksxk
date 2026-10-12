/// Per-term GPA trend (credit-weighted from each record's grade point) and
/// the blur used by the 隐藏成绩 toggle.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/edu_models.dart';

/// Blurs [child] (and hides it from screen readers) while [hidden].
class HiddenValue extends StatelessWidget {
  const HiddenValue({super.key, required this.hidden, required this.child});
  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!hidden) return child;
    return Semantics(
      label: '已隐藏',
      excludeSemantics: true,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: child,
      ),
    );
  }
}

class GpaPoint {
  const GpaPoint(this.termCode, this.termName, this.gpa, this.credits);
  final String termCode;
  final String termName;
  final double gpa;
  final double credits;

  /// `2025-2026-1` → `25秋`, `2025-2026-2` → `26春`.
  String get shortLabel {
    final m = RegExp(r'^(\d{4})-(\d{4})-(\d)').firstMatch(termCode);
    if (m == null) return termName.isEmpty ? termCode : termName;
    final first = m[3] == '1';
    final year = (first ? m[1]! : m[2]!).substring(2);
    return '$year${first ? '秋' : '春'}';
  }
}

class GpaTrend extends StatefulWidget {
  const GpaTrend({super.key, required this.records, this.hidden = false});
  final List<GradeRecord> records;
  final bool hidden;

  /// Credit-weighted GPA per term, oldest first. Records without a grade
  /// point or with no credit do not count.
  static List<GpaPoint> points(List<GradeRecord> records) {
    final sum = <String, double>{};
    final credits = <String, double>{};
    final names = <String, String>{};
    for (final r in records) {
      final gp = r.gradePoint;
      if (gp == null || r.credit <= 0 || r.termCode.isEmpty) continue;
      sum[r.termCode] = (sum[r.termCode] ?? 0) + gp * r.credit;
      credits[r.termCode] = (credits[r.termCode] ?? 0) + r.credit;
      names[r.termCode] = r.termName;
    }
    final codes = sum.keys.toList()..sort();
    return [
      for (final c in codes)
        GpaPoint(c, names[c] ?? c, sum[c]! / credits[c]!, credits[c]!),
    ];
  }

  @override
  State<GpaTrend> createState() => _GpaTrendState();
}

class _GpaTrendState extends State<GpaTrend> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = GpaTrend.points(widget.records);
    if (points.length < 2) return const SizedBox.shrink();
    final selected = (_selected ?? points.length - 1).clamp(
      0,
      points.length - 1,
    );
    final p = points[selected];
    final chart = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int nearest(Offset local) {
          final step = (width - 2 * _GpaPainter.padX) / (points.length - 1);
          return ((local.dx - _GpaPainter.padX) / step).round().clamp(
            0,
            points.length - 1,
          );
        }

        return MouseRegion(
          onHover: (e) => setState(() => _selected = nearest(e.localPosition)),
          onExit: (_) => setState(() => _selected = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) =>
                setState(() => _selected = nearest(d.localPosition)),
            onHorizontalDragUpdate: (d) =>
                setState(() => _selected = nearest(d.localPosition)),
            child: CustomPaint(
              size: Size(width, 132),
              painter: _GpaPainter(
                points: points,
                selected: selected,
                line: theme.colorScheme.primary,
                surface: theme.colorScheme.surface,
                grid: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ink: theme.colorScheme.onSurfaceVariant,
                showValues: !widget.hidden,
              ),
            ),
          ),
        );
      },
    );
    return Semantics(
      label: widget.hidden
          ? '学期绩点趋势（已隐藏）'
          : '学期绩点趋势：${points.map((e) => '${e.termName.isEmpty ? e.termCode : e.termName} ${e.gpa.toStringAsFixed(2)}').join('，')}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('学期绩点趋势', style: theme.textTheme.titleMedium),
              ),
              HiddenValue(
                hidden: widget.hidden,
                child: Text(
                  '${p.shortLabel} · ${p.gpa.toStringAsFixed(2)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          HiddenValue(hidden: widget.hidden, child: chart),
          const SizedBox(height: 6),
          Text(
            '按学分加权，只算有绩点的课程，可能与学校公布的略有出入。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _GpaPainter extends CustomPainter {
  _GpaPainter({
    required this.points,
    required this.selected,
    required this.line,
    required this.surface,
    required this.grid,
    required this.ink,
    required this.showValues,
  });
  final List<GpaPoint> points;
  final int selected;
  final Color line;
  final Color surface;
  final Color grid;
  final Color ink;
  final bool showValues;

  static const padX = 20.0;
  static const padTop = 10.0;
  static const padBottom = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = points.map((p) => p.gpa).reduce((a, b) => a < b ? a : b);
    var hi = points.map((p) => p.gpa).reduce((a, b) => a > b ? a : b);
    // Keep a sensible span so small changes are not exaggerated.
    final mid = (lo + hi) / 2;
    final span = (hi - lo).clamp(1.0, 5.0);
    lo = (mid - span / 2 - 0.1).clamp(0.0, 5.0);
    hi = lo + span + 0.2;
    final plotH = size.height - padTop - padBottom;
    final step = (size.width - 2 * padX) / (points.length - 1);
    Offset at(int i) => Offset(
      padX + i * step,
      padTop + plotH * (1 - (points[i].gpa - lo) / (hi - lo)),
    );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 2; k++) {
      final y = padTop + plotH * k / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(path)
      ..lineTo(at(points.length - 1).dx, padTop + plotH)
      ..lineTo(at(0).dx, padTop + plotH)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, padTop),
          Offset(0, padTop + plotH),
          [line.withValues(alpha: 0.18), line.withValues(alpha: 0)],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final sel = at(selected);
    canvas.drawLine(
      Offset(sel.dx, padTop),
      Offset(sel.dx, padTop + plotH),
      Paint()
        ..color = ink.withValues(alpha: 0.3)
        ..strokeWidth = 1,
    );
    for (var i = 0; i < points.length; i++) {
      final c = at(i);
      final r = i == selected ? 5.0 : 4.0;
      canvas.drawCircle(c, r + 2, Paint()..color = surface);
      canvas.drawCircle(c, r, Paint()..color = line);
    }

    for (var i = 0; i < points.length; i++) {
      // Thin the axis labels when there are many terms.
      final every = (points.length / 6).ceil();
      if (i % every != 0 && i != points.length - 1 && i != selected) continue;
      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: points[i].shortLabel,
          style: TextStyle(
            fontSize: 10,
            color: ink,
            fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      )..layout();
      final x = (at(i).dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - padBottom + 6));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_GpaPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.line != line ||
      old.showValues != showValues ||
      old.surface != surface;
}
