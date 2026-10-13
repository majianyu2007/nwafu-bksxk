/// The week grid: a swipeable pager of weeks, period rows of one height for
/// the whole term, tinted course cells, today's column and a current-time
/// line.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edu_providers.dart';
import '../../app/theme.dart';
import '../../app/ui_prefs.dart';
import '../../data/academic_calendar.dart' show schoolDate;
import '../../data/edu_models.dart';
import '../../data/timetable_logic.dart';
import '../layout.dart';
import '../widgets.dart';
import '../widgets/glass.dart';
import 'course_sheets.dart';
import 'timetable_style.dart';

class WeekPager extends ConsumerStatefulWidget {
  const WeekPager({
    super.key,
    required this.data,
    required this.week,
    required this.now,
    required this.prefs,
    required this.onWeekChanged,
  });
  final TermTimetable data;
  final int week;
  final DateTime now;
  final TimetablePrefs prefs;
  final ValueChanged<int> onWeekChanged;

  @override
  ConsumerState<WeekPager> createState() => _WeekPagerState();
}

class _WeekPagerState extends ConsumerState<WeekPager> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.week - 1);
  }

  @override
  void didUpdateWidget(WeekPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.week != widget.week) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        if (_controller.page?.round() != widget.week - 1) {
          _controller.jumpToPage(widget.week - 1);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(uiPrefsProvider);
    final periods = periodIndices(widget.data);
    final scale = layoutTextScale(context);
    final headerHeight = 52.0 * scale;
    final days = widget.prefs.showWeekend ? 7 : 5;
    return LayoutBuilder(
      builder: (context, constraints) {
        var timeWidth = 44 * scale.clamp(1.0, 1.5);
        var columnWidth = (constraints.maxWidth - timeWidth - 4) / days;
        final metrics = CellMetrics.forColumn(columnWidth);
        if (metrics.dense) {
          // Phones: a slim time column gives the days the width back.
          timeWidth = 34 * scale.clamp(1.0, 1.4);
          columnWidth = (constraints.maxWidth - timeWidth - 4) / days;
        }
        final rowHeight = termRowHeight(
          widget.data,
          columnWidth: columnWidth,
          scaler: MediaQuery.textScalerOf(context),
          compact: ui.compactTimetable,
          teacher: ui.showTeacher,
        );
        final layout = GridLayout(periods, rowHeight);
        return SizedBox(
          height: headerHeight + layout.height + 8,
          child: PageView.builder(
            controller: _controller,
            itemCount: math.max(1, widget.data.weekCount),
            onPageChanged: (index) => widget.onWeekChanged(index + 1),
            itemBuilder: (context, index) => WeekGrid(
              data: widget.data,
              week: index + 1,
              now: widget.now,
              prefs: widget.prefs,
              layout: layout,
              headerHeight: headerHeight,
              timeWidth: timeWidth,
              showTeacher: ui.showTeacher,
              metrics: metrics,
            ),
          ),
        );
      },
    );
  }
}

class WeekGrid extends ConsumerWidget {
  const WeekGrid({
    super.key,
    required this.data,
    required this.week,
    required this.now,
    required this.prefs,
    required this.layout,
    required this.headerHeight,
    required this.timeWidth,
    this.showTeacher = false,
    this.metrics = CellMetrics.regular,
  });
  final TermTimetable data;
  final int week;
  final DateTime now;
  final TimetablePrefs prefs;
  final GridLayout layout;
  final double headerHeight;
  final double timeWidth;
  final bool showTeacher;
  final CellMetrics metrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GlassTokens.of(context);
    final colors = ref.watch(courseColorsProvider);
    final today = schoolDate(now);
    final days = prefs.showWeekend ? 7 : 5;
    final minutes = cstMinutes(now);
    final lineColor = scheme.outlineVariant.withValues(alpha: 0.35);
    final monday = data.dayOf(week, 1);
    // A week never straddles May 1 / Oct 1 by more than a few days; label it
    // by its Monday and let each day's cells use their own date's times.
    final season = BellSeason.of(monday);

    // Today's ongoing class, else the next one today, glows.
    CourseSession? highlight;
    var highlightOngoing = false;
    if (data.weekOf(today) == week) {
      for (final s in data.sessionsOn(week, today.weekday)) {
        final st = statusOf(data, s, today, now);
        if (st == ClassStatus.ongoing) {
          highlight = s;
          highlightOngoing = true;
          break;
        }
        if (st == ClassStatus.soon || st == ClassStatus.later) {
          highlight ??= s;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.fill(tokens.cardSurfaceAlpha * 0.7),
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: timeWidth,
              child: Column(
                children: [
                  SizedBox(
                    height: headerHeight,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${monday.month}月',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            season == BellSeason.summer ? '夏令' : '冬令',
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: layout.height,
                    child: Stack(
                      children: [
                        for (final index in layout.periods)
                          Positioned(
                            top: layout.top(index),
                            height: layout.rowHeight,
                            left: 0,
                            right: 0,
                            child: _PeriodLabel(
                              index: index,
                              period: data.period(index, on: monday),
                              dense: metrics.dense,
                            ),
                          ),
                        for (final (y, label) in layout.breaks)
                          Positioned(
                            top: y,
                            height: kBreakHeight,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (var day = 1; day <= days; day++)
              Expanded(
                // An empty weekend gets half a column so the weekdays,
                // where the classes are, get the width.
                flex:
                    day >= 6 &&
                        metrics.dense &&
                        !data.sessions.any(
                          (s) =>
                              s.weekday == day &&
                              (s.runsInWeek(week) || prefs.showOtherWeeks),
                        )
                    ? 1
                    : 2,
                child: _DayColumn(
                  data: data,
                  week: week,
                  day: day,
                  isToday: data.dayOf(week, day) == today,
                  layout: layout,
                  headerHeight: headerHeight,
                  lineColor: lineColor,
                  showOtherWeeks: prefs.showOtherWeeks,
                  showTeacher: showTeacher,
                  metrics: metrics,
                  colors: colors,
                  nowLine: data.dayOf(week, day) == today
                      ? nowOffset(data, layout, today, minutes)
                      : null,
                  highlight: data.dayOf(week, day) == today ? highlight : null,
                  highlightOngoing: highlightOngoing,
                ),
              ),
            SizedBox(width: metrics.dense ? 2 : 4),
          ],
        ),
      ),
    );
  }
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({
    required this.index,
    required this.period,
    this.dense = false,
  });
  final int index;
  final ClassPeriod? period;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      fontSize: dense ? 9 : 10.5,
      height: 1.2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final p = period;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$index',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: dense ? 13 : 15,
          ),
        ),
        if (p != null) ...[
          Text(p.startLabel, style: muted, softWrap: false),
          Text(p.endLabel, style: muted, softWrap: false),
        ],
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.data,
    required this.week,
    required this.day,
    required this.isToday,
    required this.layout,
    required this.headerHeight,
    required this.lineColor,
    required this.showOtherWeeks,
    required this.showTeacher,
    required this.metrics,
    required this.colors,
    required this.nowLine,
    required this.highlight,
    required this.highlightOngoing,
  });
  final TermTimetable data;
  final int week;
  final int day;
  final bool isToday;
  final GridLayout layout;
  final double headerHeight;
  final Color lineColor;
  final bool showOtherWeeks;
  final bool showTeacher;
  final CellMetrics metrics;
  final CourseColors colors;
  final double? nowLine;
  final CourseSession? highlight;
  final bool highlightOngoing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = data.dayOf(week, day);
    final groups = overlapGroups(
      data.sessions
          .where(
            (s) =>
                s.weekday == day &&
                layout.top(s.startPeriod) != null &&
                layout.top(s.endPeriod) != null &&
                (s.runsInWeek(week) || showOtherWeeks),
          )
          .toList(),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday ? scheme.primary.withValues(alpha: 0.07) : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SizedBox(
            height: headerHeight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    metrics.dense
                        ? kWeekdayNames[day - 1].substring(1)
                        : kWeekdayNames[day - 1],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: isToday
                        ? BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          )
                        : null,
                    child: Text(
                      isToday ? '今' : '${date.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isToday ? scheme.onPrimary : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: layout.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final index in layout.periods)
                  Positioned(
                    top: layout.top(index),
                    height: layout.rowHeight,
                    left: 0,
                    right: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: lineColor)),
                      ),
                    ),
                  ),
                for (final (y, _) in layout.breaks)
                  Positioned(
                    top: y,
                    height: kBreakHeight,
                    left: 0,
                    right: 0,
                    child: ColoredBox(
                      color: scheme.onSurface.withValues(alpha: 0.03),
                    ),
                  ),
                for (final group in groups)
                  _positioned(
                    group,
                    child: CourseCell(
                      data: data,
                      group: group,
                      week: week,
                      color: colors.of(_primary(group, week)),
                      showTeacher: showTeacher,
                      metrics: metrics,
                      glow: highlight != null && group.contains(highlight),
                      ongoing: _ongoing(group),
                      progress: _ongoing(group) ? _progressIn(group) : null,
                    ),
                  ),
                if (nowLine case final y? when !_lineInsideOngoing(groups))
                  Positioned(
                    top: y - 4,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Semantics(
                        label: '当前时间',
                        child: _NowLine(color: scheme.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _ongoing(List<CourseSession> group) =>
      highlightOngoing && highlight != null && group.contains(highlight);

  /// The now line is drawn as the class's own progress instead of a stroke
  /// across its text.
  bool _lineInsideOngoing(List<List<CourseSession>> groups) =>
      groups.any(_ongoing);

  double? _progressIn(List<CourseSession> group) {
    final y = nowLine;
    if (y == null) return null;
    final top = layout.top(group.first.startPeriod)!;
    final bottom = layout.bottom(
      group.map((s) => s.endPeriod).reduce(math.max),
    );
    return ((y - top) / (bottom - top)).clamp(0.0, 1.0);
  }

  Widget _positioned(List<CourseSession> group, {required Widget child}) {
    final top = layout.top(group.first.startPeriod)!;
    final bottom = layout.bottom(
      group.map((s) => s.endPeriod).reduce(math.max),
    );
    return Positioned(
      top: top + 2,
      height: bottom - top - 4,
      left: CellMetrics.inset,
      right: CellMetrics.inset,
      child: child,
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter(this.color, this.progress);
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 3.0;
    final y = size.height * progress;
    canvas
      ..drawRect(
        Rect.fromLTWH(0, 0, w, size.height),
        Paint()..color = color.withValues(alpha: 0.35),
      )
      ..drawRect(Rect.fromLTWH(0, 0, w, y), Paint()..color = color)
      ..drawCircle(
        Offset(w / 2 + 0.5, y.clamp(4.0, size.height - 4)),
        4,
        Paint()..color = color,
      );
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) =>
      old.color != color || old.progress != progress;
}

CourseSession _primary(List<CourseSession> group, int week) {
  final active = group.where((s) => s.runsInWeek(week));
  return active.isEmpty ? group.first : active.first;
}

/// One cell of the grid: tinted surface, 3 px accent bar, top sheen, the full
/// course name wrapped, then the room (and optionally the teacher).
class CourseCell extends StatelessWidget {
  const CourseCell({
    super.key,
    required this.data,
    required this.group,
    required this.week,
    required this.color,
    this.showTeacher = false,
    this.metrics = CellMetrics.regular,
    this.glow = false,
    this.ongoing = false,
    this.progress,
  });
  final TermTimetable data;
  final List<CourseSession> group;
  final int week;
  final Color color;
  final bool showTeacher;
  final CellMetrics metrics;
  final bool glow;
  final bool ongoing;

  /// How far through the class "now" is (0–1), for the class in progress.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final active = group.where((s) => s.runsInWeek(week)).toList();
    final session = active.isEmpty ? group.first : active.first;
    final other = active.isEmpty;
    final accent = other ? scheme.outline : color;
    final fill = other
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.55)
        : cellFill(context, color, now: ongoing);
    final ink = other ? scheme.onSurfaceVariant : cellInk(context, color);
    final text = cellText(session, teacher: showTeacher, dense: metrics.dense);
    final radius = BorderRadius.circular(tokens.cellRadius);
    final fullLabel = group
        .map(
          (s) =>
              '${s.displayName}，第${s.startPeriod}至${s.endPeriod}节，'
              '${s.room}，${s.runsInWeek(week) ? '本周有课' : '非本周课程'}',
        )
        .join('；');

    void open() => showCourseDetails(context, data, group, week);
    void copyRoom() {
      if (session.room.isEmpty) return;
      Clipboard.setData(ClipboardData(text: session.room));
      showToast(context, '已复制教室：${session.room}');
    }

    return Semantics(
      button: true,
      label: fullLabel,
      onTap: open,
      onLongPress: copyRoom,
      child: Tooltip(
        message: fullLabel,
        waitDuration: const Duration(milliseconds: 600),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            // One soft, even lift in the course colour; no hard outline.
            boxShadow: glow && !other
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: ongoing ? 0.35 : 0.18),
                      blurRadius: ongoing ? 18 : 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                color: fill,
                gradient: tokens.enabled ? sheenGradient(tokens, fill) : null,
                border: glow && !other
                    ? Border.all(
                        color: color.withValues(alpha: ongoing ? 0.55 : 0.3),
                      )
                    : null,
              ),
              child: InkWell(
                onTap: open,
                onLongPress: copyRoom,
                child: ExcludeSemantics(
                  child: Stack(
                    children: [
                      if (progress case final p?)
                        // Progress lives in the accent bar only, so nothing
                        // crosses the course name: elapsed part bright, the
                        // rest dim, a dot at "now".
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 10,
                          child: CustomPaint(
                            painter: _ProgressBarPainter(color, p),
                          ),
                        ),
                      if (other)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: HatchPainter(
                              scheme.outline.withValues(alpha: 0.16),
                            ),
                          ),
                        ),
                      if (progress == null)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 3,
                          child: ColoredBox(
                            color: accent.withValues(alpha: other ? 0.4 : 1),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          metrics.padH + 3,
                          metrics.padV,
                          metrics.padH,
                          metrics.padV,
                        ),
                        child: _CellText(
                          metrics: metrics,
                          badge: glow && !other
                              ? (ongoing ? '上课中' : '下一节')
                              : null,
                          badgeColor: color,
                          name: text.name,
                          meta: text.meta,
                          ink: ink,
                          other: other,
                          // Only classes meeting this week can clash; other
                          // weeks' classes in the same slot are not overlaps.
                          extra: active.length > 1 ? active.length : 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _textWidth(String text, TextStyle style) {
  final p = TextPainter(
    textDirection: TextDirection.ltr,
    maxLines: 1,
    text: TextSpan(text: text, style: style),
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

class _CellText extends StatelessWidget {
  const _CellText({
    required this.metrics,
    this.badge,
    this.badgeColor,
    required this.name,
    required this.meta,
    required this.ink,
    required this.other,
    required this.extra,
  });
  final CellMetrics metrics;
  final String name;
  final String meta;
  final Color ink;
  final bool other;
  final int extra;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final inkStyle = TextStyle(color: ink.withValues(alpha: other ? 0.8 : 1));
    return LayoutBuilder(
      builder: (context, box) {
        final nameSize = metrics.dense
            ? fittedNameSize(name, box.maxWidth, metrics.name)
            : metrics.name;
        final lines = meta.isEmpty ? const <String>[] : meta.split('\n');
        final head = Text.rich(
          TextSpan(
            children: [
              if (badge != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.dense ? 4 : 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      metrics.dense ? (badge == '上课中' ? '上课' : '下节') : badge!,
                      style: TextStyle(
                        fontSize: metrics.dense ? 9.5 : 10.5,
                        fontWeight: FontWeight.w700,
                        color:
                            ThemeData.estimateBrightnessForColor(badgeColor!) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              if (badge != null) const TextSpan(text: '\n'),
              if (other)
                const TextSpan(
                  text: '非本周\n',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600),
                ),
              if (extra > 1)
                TextSpan(
                  text: '$extra 项重叠\n',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              TextSpan(
                text: name,
                style: TextStyle(
                  fontSize: nameSize,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          style: inkStyle,
        );
        final metaStyle = inkStyle.copyWith(
          fontSize: metrics.meta,
          height: 1.2,
          fontWeight: FontWeight.w500,
        );
        // Clip rather than overflow if a very long name meets the row cap.
        return ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              head,
              for (final line in lines)
                // A short room code ("N9308") is one unit: shrink it a
                // little onto one line rather than split it. Long names
                // ("计算机机房202-B") wrap normally instead of going tiny.
                metrics.dense &&
                        _textWidth(line, metaStyle) <= box.maxWidth / 0.8
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(line, style: metaStyle, maxLines: 1),
                      )
                    : Text(line, style: metaStyle),
            ],
          ),
        );
      },
    );
  }
}
