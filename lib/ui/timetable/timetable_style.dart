/// Shared timetable helpers: course colours, labels, the per-term row height
/// and the "where is now" arithmetic used by both the week grid and the day
/// view.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edu_providers.dart';
import '../../app/theme.dart';
import '../../app/ui_prefs.dart';
import '../../data/edu_models.dart';
import '../../data/timetable_logic.dart';

/// The key a course's colour is stored under: its code, else its name.
String courseKey(CourseSession s) =>
    s.courseCode.isEmpty ? s.displayName : s.courseCode;

/// Resolves course colours for the signed-in account (user override first,
/// then the stable palette).
class CourseColors {
  const CourseColors(this.account, this.overrides);
  final String account;
  final Map<String, int> overrides;

  Color of(CourseSession s) {
    final custom = overrides[courseColorKey(account, courseKey(s))];
    return custom != null ? Color(custom) : courseColorFor(courseKey(s));
  }

  bool isCustom(CourseSession s) =>
      overrides.containsKey(courseColorKey(account, courseKey(s)));
}

final courseColorsProvider = Provider<CourseColors>((ref) {
  final account =
      ref.watch(eduSessionProvider.select((s) => s.account?.username)) ?? '';
  return CourseColors(
    account,
    ref.watch(uiPrefsProvider.select((p) => p.courseColors)),
  );
});

/// Cell background: the surface blended with the course colour.
Color cellFill(BuildContext context, Color course, {bool now = false}) {
  final t = GlassTokens.of(context);
  final base = Theme.of(context).colorScheme.surface;
  return Color.alphaBlend(
    course.withValues(alpha: now ? t.cellTintNow : t.cellTint),
    t.enabled ? base.withValues(alpha: 0.82) : base,
  );
}

/// Readable text colour on a cell tinted with [course].
Color cellInk(BuildContext context, Color course) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Color.lerp(scheme.onSurface, course, dark ? 0.25 : 0.35)!;
}

/// Every period row the grid shows: the school's periods 1–11 plus any
/// later period a session actually uses (the server's table lists 12–13,
/// which no class uses, and empty rows only make the grid look sparse).
List<int> periodIndices(TermTimetable data) {
  final indices = <int>{
    for (final period in ClassPeriod.nwafuWinter) period.index,
  };
  for (final session in data.sessions) {
    if (session.startPeriod > 0 && session.endPeriod >= session.startPeriod) {
      for (var p = session.startPeriod; p <= session.endPeriod; p++) {
        indices.add(p);
      }
    }
  }
  return indices.toList()..sort();
}

/// Connected overlapping intervals share one cell, so no class can cover
/// another or become an impossibly narrow tap target on a phone.
List<List<CourseSession>> overlapGroups(List<CourseSession> sessions) {
  final sorted = [...sessions]
    ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  final groups = <List<CourseSession>>[];
  var end = -1;
  for (final session in sorted) {
    if (groups.isEmpty || session.startPeriod > end) {
      groups.add([session]);
      end = session.endPeriod;
    } else {
      groups.last.add(session);
      end = math.max(end, session.endPeriod);
    }
  }
  return groups;
}

/// Text sizes and padding of a grid cell. Phones get [dense] metrics (as in
/// WakeUp): seven columns of ~50 px cannot fit 14 px names without wrapping
/// every two characters.
class CellMetrics {
  const CellMetrics._(this.padH, this.padV, this.name, this.meta, this.dense);
  final double padH;
  final double padV;
  final double name;
  final double meta;
  final bool dense;

  static const regular = CellMetrics._(5, 6, 14, 12, false);
  static const narrow = CellMetrics._(3, 4, 12.5, 10.5, true);

  /// Below this column width the grid switches to [narrow].
  static const denseBelow = 72.0;

  static CellMetrics forColumn(double columnWidth) =>
      columnWidth < denseBelow ? narrow : regular;

  /// Horizontal inset of a cell inside its column (each side).
  static const double inset = 2;

  /// Width left for text in a cell of [columnWidth] (accent bar included).
  double textWidth(double columnWidth) =>
      math.max(12.0, columnWidth - 2 * inset - 2 * padH - 3);
}

/// Text shown in one cell, line by line. Dense cells drop the `@`.
({String name, String meta}) cellText(
  CourseSession s, {
  bool teacher = false,
  bool dense = false,
}) {
  final meta = [
    if (s.room.isNotEmpty) dense ? s.room : '@${s.room}',
    if (teacher && s.teacher.isNotEmpty) s.teacher,
  ].join('\n');
  return (name: s.displayName, meta: meta);
}

/// One row height for the whole term so every week lines up: tall enough
/// that the longest course name (wrapped, not cut) plus its room fits in the
/// periods it spans, between [minRow] and [maxRow].
double termRowHeight(
  TermTimetable data, {
  required double columnWidth,
  required TextScaler scaler,
  required bool compact,
  required bool teacher,
}) {
  final m = CellMetrics.forColumn(columnWidth);
  final minRow = compact ? 52.0 : (m.dense ? 56.0 : 60.0);
  final maxRow = compact ? 80.0 : 140.0;
  if (compact) return scaler.scale(minRow);
  final inner = m.textWidth(columnWidth);
  var need = minRow;
  for (final s in data.sessions) {
    if (s.startPeriod < 1 || s.endPeriod < s.startPeriod) continue;
    final text = cellText(s, teacher: teacher, dense: m.dense);
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      text: TextSpan(
        children: [
          TextSpan(
            text: text.name,
            style: TextStyle(
              fontSize: m.name,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (text.meta.isNotEmpty)
            TextSpan(
              text: '\n${text.meta}',
              style: TextStyle(fontSize: m.meta, height: 1.2),
            ),
        ],
      ),
    )..layout(maxWidth: inner);
    final span = s.endPeriod - s.startPeriod + 1;
    // + the 2 px gap above and below each cell.
    need = math.max(need, (painter.height + 2 * m.padV + 4) / span);
    painter.dispose();
  }
  return math.min(need, scaler.scale(maxRow)).ceilToDouble();
}

/// Minutes after midnight, China Standard Time.
int cstMinutes(DateTime instant) {
  final cst = instant.toUtc().add(const Duration(hours: 8));
  return cst.hour * 60 + cst.minute;
}

/// Breaks of the bell schedule drawn between period rows, so the grid reads
/// like the school's 作息时间表: 午休 after period 4, 晚饭 after period 8.
const kGridBreaks = {4: '午休', 8: '晚饭'};
const double kBreakHeight = 18;

/// Row geometry of the week grid: period rows of one height with labelled
/// break bands between the morning, afternoon and evening blocks.
class GridLayout {
  GridLayout(this.periods, this.rowHeight) {
    var y = 0.0;
    for (var i = 0; i < periods.length; i++) {
      _top.add(y);
      y += rowHeight;
      if (i < periods.length - 1 && kGridBreaks.containsKey(periods[i])) {
        _breakAt.add(y);
        y += kBreakHeight;
      }
    }
    height = y;
  }

  final List<int> periods;
  final double rowHeight;
  final _top = <double>[];
  final _breakAt = <double>[];
  late final double height;

  /// Top of period [index]'s row, or null when not shown.
  double? top(int index) {
    final i = periods.indexOf(index);
    return i < 0 ? null : _top[i];
  }

  double bottom(int index) => top(index)! + rowHeight;

  /// (y, label) of each break band.
  Iterable<(double, String)> get breaks sync* {
    var k = 0;
    for (var i = 0; i < periods.length - 1; i++) {
      final label = kGridBreaks[periods[i]];
      if (label != null) yield (_breakAt[k++], label);
    }
  }
}

/// Vertical offset of [minutes] (CST) on [date] within [layout], interpolated
/// inside a period and pinned to the band during a break. Null before the
/// first or after the last period.
double? nowOffset(
  TermTimetable data,
  GridLayout layout,
  DateTime date,
  int minutes,
) {
  double? previousEnd;
  for (final index in layout.periods) {
    final p = data.period(index, on: date);
    if (p == null) continue;
    final top = layout.top(index)!;
    if (minutes < p.start) {
      if (previousEnd == null) return null;
      return previousEnd + (top - previousEnd) / 2;
    }
    if (minutes <= p.end) {
      final f = p.end == p.start
          ? 0.0
          : (minutes - p.start) / (p.end - p.start);
      return top + f * layout.rowHeight;
    }
    previousEnd = top + layout.rowHeight;
  }
  return null;
}

/// What a class on [date] is doing at [now].
enum ClassStatus { ongoing, soon, done, later, unknown }

ClassStatus statusOf(
  TermTimetable data,
  CourseSession s,
  DateTime date,
  DateTime now,
) {
  final o = data.occurrence(s, date);
  if (o == null) return ClassStatus.unknown;
  if (!now.isBefore(o.end)) return ClassStatus.done;
  if (!now.isBefore(o.start)) return ClassStatus.ongoing;
  if (o.start.difference(now) <= const Duration(minutes: 30)) {
    return ClassStatus.soon;
  }
  return ClassStatus.later;
}

String timeLabel(TermTimetable data, CourseSession session, {DateTime? on}) {
  final start = data.period(session.startPeriod, on: on);
  final end = data.period(session.endPeriod, on: on);
  final periods = '第 ${session.startPeriod}–${session.endPeriod} 节';
  return start == null || end == null
      ? periods
      : '$periods · ${start.startLabel}–${end.endLabel}';
}

String dateLabel(DateTime date) => '${date.month}月${date.day}日';

String weekdayLabel(int weekday) =>
    weekday >= 1 && weekday <= 7 ? kWeekdayNames[weekday - 1] : '星期未提供';

String syncLabel(DateTime instant) {
  final cst = instant.toUtc().add(const Duration(hours: 8));
  return '${cst.month}/${cst.day} '
      '${cst.hour.toString().padLeft(2, '0')}:'
      '${cst.minute.toString().padLeft(2, '0')} 更新';
}

/// Exam date as a UTC-midnight calendar day, when the free text contains
/// one (`2027-01-10`, `2027/1/10`, `2027年1月10日`).
DateTime? examDate(ExamEntry e) {
  final m = RegExp(
    r'(\d{4})\s*[-/年.]\s*(\d{1,2})\s*[-/月.]\s*(\d{1,2})',
  ).firstMatch('${e.date} ${e.time}');
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// Diagonal hatch for classes that do not run in the shown week.
class HatchPainter extends CustomPainter {
  const HatchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const gap = 7.0;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(HatchPainter old) => old.color != color;
}
