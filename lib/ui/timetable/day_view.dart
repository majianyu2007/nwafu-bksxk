/// The day view: a strip of the selected week's dates and a vertical
/// timeline of the chosen day's classes with live status.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/academic_calendar.dart' show schoolDate;
import '../../data/edu_models.dart';
import '../../data/timetable_logic.dart';
import '../widgets.dart';
import '../widgets/glass.dart';
import 'course_sheets.dart';
import 'timetable_style.dart';

/// Date strip for [week]; [selected] is a weekday (1–7).
class DateStrip extends StatelessWidget {
  const DateStrip({
    super.key,
    required this.data,
    required this.week,
    required this.selected,
    required this.now,
    required this.onSelect,
    this.exams = const [],
  });
  final TermTimetable data;
  final int week;
  final int selected;
  final DateTime now;
  final ValueChanged<int> onSelect;
  final List<ExamEntry> exams;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = schoolDate(now);
    final examDays = {for (final e in exams) ?examDate(e)};
    return Row(
      children: [
        for (var d = 1; d <= 7; d++)
          Expanded(
            child: Builder(
              builder: (context) {
                final date = data.dayOf(week, d);
                final isSel = d == selected;
                final isToday = date == today;
                final count = data.sessionsOn(week, d).length;
                return Semantics(
                  button: true,
                  selected: isSel,
                  label: '${kWeekdayNames[d - 1]} ${dateLabel(date)}，$count 节课',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onSelect(d),
                    child: AnimatedContainer(
                      duration: reduceMotion(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSel
                            ? scheme.primary
                            : isToday
                            ? scheme.primary.withValues(alpha: 0.10)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            kWeekdayNames[d - 1].substring(1),
                            style: TextStyle(
                              fontSize: 11,
                              color: isSel
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isToday ? '今' : '${date.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isSel
                                  ? scheme.onPrimary
                                  : isToday
                                  ? scheme.primary
                                  : scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < count.clamp(0, 3); i++)
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSel
                                        ? scheme.onPrimary
                                        : scheme.primary,
                                  ),
                                ),
                              if (examDays.contains(date))
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.only(left: 2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: scheme.error,
                                  ),
                                ),
                              if (count == 0 && !examDays.contains(date))
                                const SizedBox(height: 4),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The classes of one day as a timeline.
class DayTimeline extends ConsumerWidget {
  const DayTimeline({
    super.key,
    required this.data,
    required this.week,
    required this.weekday,
    required this.now,
    required this.showOtherWeeks,
    this.exams = const [],
    this.onAdd,
  });
  final TermTimetable data;
  final int week;
  final int weekday;
  final DateTime now;
  final bool showOtherWeeks;
  final List<ExamEntry> exams;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(courseColorsProvider);
    final scheme = Theme.of(context).colorScheme;
    final date = data.dayOf(week, weekday);
    final sessions = data.sessionsOn(week, weekday);
    final others = showOtherWeeks
        ? ([
            for (final s in data.sessions)
              if (s.weekday == weekday && !s.runsInWeek(week)) s,
          ]..sort((a, b) => a.startPeriod.compareTo(b.startPeriod)))
        : const <CourseSession>[];
    final todaysExams = [
      for (final e in exams)
        if (examDate(e) == date) e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            '${dateLabel(date)} · ${kWeekdayNames[weekday - 1]} · '
            '${sessions.isEmpty ? '无课' : '${sessions.length} 节课'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final e in todaysExams)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              tint: scheme.error,
              tintAmount: 0.12,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.assignment_outlined, color: scheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '考试 · ${e.courseName}'
                      '${e.time.isEmpty ? '' : '\n${e.time}'}'
                      '${e.room.isEmpty ? '' : ' · ${e.room}'}'
                      '${e.seat.isEmpty ? '' : ' · 座位 ${e.seat}'}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (sessions.isEmpty && todaysExams.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(
              children: [
                Icon(
                  Icons.free_breakfast_outlined,
                  size: 40,
                  color: scheme.primary,
                ),
                const SizedBox(height: 12),
                const Text('这一天没有课程', textAlign: TextAlign.center),
                if (onAdd != null)
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('添加课程'),
                  ),
              ],
            ),
          ),
        for (var i = 0; i < sessions.length; i++)
          _TimelineItem(
            data: data,
            session: sessions[i],
            week: week,
            date: date,
            now: now,
            color: colors.of(sessions[i]),
            last: i == sessions.length - 1,
          ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '非本周课程',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          for (final s in others)
            Opacity(
              opacity: 0.6,
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(s.displayName),
                subtitle: Text('${timeLabel(data, s)} · ${s.weeksLabel}'),
                onTap: () => showCourseDetails(context, data, [s], week),
              ),
            ),
        ],
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.data,
    required this.session,
    required this.week,
    required this.date,
    required this.now,
    required this.color,
    required this.last,
  });
  final TermTimetable data;
  final CourseSession session;
  final int week;
  final DateTime date;
  final DateTime now;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GlassTokens.of(context);
    final status = statusOf(data, session, date, now);
    final start = data.period(session.startPeriod, on: date);
    final end = data.period(session.endPeriod, on: date);
    final (label, labelColor) = switch (status) {
      ClassStatus.ongoing => ('进行中', color),
      ClassStatus.soon => ('即将开始', scheme.tertiary),
      ClassStatus.done => ('已结束', scheme.outline),
      _ => ('', scheme.outline),
    };
    final done = status == ClassStatus.done;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 12),
                Text(
                  start?.startLabel ?? '第${session.startPeriod}节',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  end?.endLabel ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? scheme.outlineVariant : color,
                    boxShadow: status == ClassStatus.ongoing
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: done ? 0.6 : 1,
                child: Semantics(
                  button: true,
                  label:
                      '${session.displayName}，${timeLabel(data, session, on: date)}'
                      '${session.room.isEmpty ? '' : '，${session.room}'}'
                      '${label.isEmpty ? '' : '，$label'}',
                  excludeSemantics: true,
                  child: GlassCard(
                    tint: color,
                    tintAmount: status == ClassStatus.ongoing
                        ? tokens.cellTintNow
                        : tokens.cellTint,
                    radius: 16,
                    padding: EdgeInsets.zero,
                    onTap: () =>
                        showCourseDetails(context, data, [session], week),
                    onLongPress: session.room.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(text: session.room),
                            );
                            showToast(context, '已复制教室：${session.room}');
                          },
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 3,
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                12,
                                12,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          session.displayName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      if (label.isNotEmpty)
                                        StatusPill(
                                          label: label,
                                          color: labelColor,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      _Meta(
                                        Icons.schedule,
                                        '第 ${session.startPeriod}–${session.endPeriod} 节',
                                      ),
                                      if (session.room.isNotEmpty)
                                        _Meta(
                                          Icons.place_outlined,
                                          session.room,
                                        ),
                                      if (session.teacher.isNotEmpty)
                                        _Meta(
                                          Icons.person_outline,
                                          session.teacher,
                                        ),
                                    ],
                                  ),
                                ],
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
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    );
  }
}
