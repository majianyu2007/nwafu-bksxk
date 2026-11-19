/// Selection-preview weekly timetable, styled to match the main Glass timetable.
/// Calendar calibration is independent of course rows; a course that starts
/// later in the term never moves the current week.
library;

import 'package:flutter/material.dart';

import '../app/theme.dart' show courseColorFor;
import '../data/academic_calendar.dart';
import '../data/models.dart';
import '../data/timetable_logic.dart' show kWeekdayNames;
import 'layout.dart';
import 'widgets.dart';
import 'widgets/glass.dart';

Color _accentFor(ScheduleEntry entry) => courseColorFor(
  entry.teachingClassId.isNotEmpty ? entry.teachingClassId : entry.courseName,
);

class WeeklyTimetable extends StatefulWidget {
  const WeeklyTimetable({
    super.key,
    required this.entries,
    required this.term,
    required this.calendar,
    required this.today,
    required this.onCalibrate,
  });

  final List<ScheduleEntry> entries;
  final AcademicTerm term;
  final AcademicCalendar? calendar;
  final DateTime today;
  final VoidCallback onCalibrate;

  @override
  State<WeeklyTimetable> createState() => _WeeklyTimetableState();
}

class _WeeklyTimetableState extends State<WeeklyTimetable> {
  // Null follows the calendar; browsing another week never mutates calibration.
  int? _browsingWeek;

  @override
  void didUpdateWidget(covariant WeeklyTimetable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.term.id != widget.term.id ||
        oldWidget.calendar?.firstMonday != widget.calendar?.firstMonday ||
        oldWidget.calendar?.weekCount != widget.calendar?.weekCount) {
      _browsingWeek = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final calendar = widget.calendar;
    final currentWeek = calendar?.weekOn(widget.today);
    var maxWeek = calendar?.weekCount ?? 20;
    for (final entry in widget.entries) {
      final weeks = entry.weeks;
      if (weeks.isNotEmpty && weeks.last > maxWeek) maxWeek = weeks.last;
    }
    final week = (_browsingWeek ?? calendar?.browsingWeekOn(widget.today) ?? 1)
        .clamp(1, maxWeek);
    final monday = calendar?.mondayOf(week);
    final blocks =
        widget.entries
            .where((entry) => entry.hasSlot && entry.weeks.contains(week))
            .toList()
          ..sort((a, b) {
            var order = a.dayOfWeek.compareTo(b.dayOfWeek);
            if (order != 0) return order;
            order = a.beginSection.compareTo(b.beginSection);
            return order != 0 ? order : a.courseName.compareTo(b.courseName);
          });
    final unscheduled = widget.entries
        .where((entry) => !entry.hasSlot || entry.weeks.isEmpty)
        .toList();
    final conflicts = <ScheduleEntry, List<ScheduleEntry>>{};
    for (var i = 0; i < blocks.length; i++) {
      for (var j = i + 1; j < blocks.length; j++) {
        final first = blocks[i];
        final second = blocks[j];
        if (second.dayOfWeek != first.dayOfWeek) break;
        final end = first.endSection < first.beginSection
            ? first.beginSection
            : first.endSection;
        if (second.beginSection > end) break;
        (conflicts[first] ??= []).add(second);
        (conflicts[second] ??= []).add(first);
      }
    }
    final status = calendar == null
        ? '尚未校准当前周'
        : currentWeek != null
        ? '第 $currentWeek 周'
        : calendar.hasNotStarted(widget.today)
        ? '学期尚未开始'
        : '已超出已设周数';
    final hasWeekend = blocks.any((b) => b.dayOfWeek >= 6);

    Widget course(ScheduleEntry entry, {bool compact = false}) => _CourseBlock(
      entry: entry,
      compact: compact,
      conflicts: conflicts[entry] ?? const [],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.term.label} · $status',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${monday == null ? '浏览第 $week 周' : '${_date(monday)} – ${_date(monday.add(const Duration(days: 6)))}'} · ${blocks.length} 次课程',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onCalibrate,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                    label: const Text('校准'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '上一周',
                          visualDensity: VisualDensity.compact,
                          onPressed: week > 1
                              ? () => setState(() => _browsingWeek = week - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left, size: 20),
                        ),
                        DropdownButton<int>(
                          value: week,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                          items: [
                            for (var w = 1; w <= maxWeek; w++)
                              DropdownMenuItem(
                                value: w,
                                child: Text('第 $w 周'),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _browsingWeek = value),
                        ),
                        IconButton(
                          tooltip: '下一周',
                          visualDensity: VisualDensity.compact,
                          onPressed: week < maxWeek
                              ? () => setState(() => _browsingWeek = week + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right, size: 20),
                        ),
                      ],
                    ),
                  ),
                  if (currentWeek != null && week != currentWeek)
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() => _browsingWeek = null),
                      icon: const Icon(Icons.today_outlined, size: 16),
                      label: const Text('回到本周'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          NoticeStrip(
            text: '${conflicts.length} 次课程存在时间重叠，点按卡片可查看冲突详情。',
            icon: Icons.warning_amber_rounded,
            error: true,
            margin: EdgeInsets.zero,
          ),
        ],
        const SizedBox(height: 12),
        if (blocks.isEmpty)
          const GlassCard(
            child: EmptyState(
              icon: Icons.event_available_outlined,
              title: '本周没有已排课程',
              subtitle: '可切换周次查看其他周的安排',
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              if (constraints.maxWidth < 720 || scale > 1.35) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      if (blocks.any((entry) => entry.dayOfWeek == day)) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DayHeader(
                                  day: day,
                                  date: monday?.add(Duration(days: day - 1)),
                                  today: widget.today,
                                ),
                                const SizedBox(height: 10),
                                for (final entry in blocks)
                                  if (entry.dayOfWeek == day)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: course(entry),
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ],
                  ],
                );
              }
              return _WeekGrid(
                blocks: blocks,
                monday: monday,
                today: widget.today,
                days: hasWeekend ? 7 : 5,
                course: (entry) => course(entry, compact: true),
              );
            },
          ),
        if (unscheduled.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '待公布时间 / 周次',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          AdaptiveGrid(
            minColumnWidth: 280,
            maxColumns: 3,
            spacing: 10,
            runSpacing: 10,
            children: [for (final entry in unscheduled) course(entry)],
          ),
        ],
      ],
    );
  }
}

String _date(DateTime date) => '${date.month}/${date.day}';

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.date,
    required this.today,
    this.centered = false,
  });
  final int day;
  final DateTime? date;
  final DateTime today;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToday = date == calendarDate(today);
    final label = kWeekdayNames[day - 1];
    final dateText = date == null ? '' : '${date!.month}/${date!.day}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isToday
            ? scheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: centered
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isToday ? scheme.primary : scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (dateText.isNotEmpty)
                  Text(
                    dateText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            )
          : Row(
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isToday ? scheme.primary : scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (dateText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    dateText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (isToday) ...[
                  const SizedBox(width: 8),
                  StatusPill(label: '今天', color: scheme.primary),
                ],
              ],
            ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.blocks,
    required this.monday,
    required this.today,
    required this.days,
    required this.course,
  });
  final List<ScheduleEntry> blocks;
  final DateTime? monday;
  final DateTime today;
  final int days;
  final Widget Function(ScheduleEntry) course;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final divider = scheme.outlineVariant.withValues(alpha: 0.24);
    const periods = [
      (label: '上午', range: '1–4', begin: 1, end: 4),
      (label: '下午', range: '5–8', begin: 5, end: 8),
      (label: '晚上', range: '9–11', begin: 9, end: 1000),
    ];

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 48),
              for (var day = 1; day <= days; day++)
                Expanded(
                  child: _DayHeader(
                    day: day,
                    date: monday?.add(Duration(days: day - 1)),
                    today: today,
                    centered: true,
                  ),
                ),
            ],
          ),
          Divider(height: 14, color: divider),
          for (var pIdx = 0; pIdx < periods.length; pIdx++) ...[
            if (pIdx > 0) Divider(height: 14, color: divider),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 48,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          periods[pIdx].label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          periods[pIdx].range,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var day = 1; day <= days; day++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              monday?.add(Duration(days: day - 1)) ==
                                  calendarDate(today)
                              ? scheme.primary.withValues(alpha: 0.045)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final entry in blocks)
                              if (entry.dayOfWeek == day &&
                                  entry.beginSection >= periods[pIdx].begin &&
                                  entry.beginSection <= periods[pIdx].end)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: course(entry),
                                ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    required this.entry,
    required this.conflicts,
    required this.compact,
  });
  final ScheduleEntry entry;
  final List<ScheduleEntry> conflicts;
  final bool compact;

  Future<void> _details(BuildContext context) => showAdaptiveSheet<void>(
    context,
    scrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry.courseName,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            DetailRow('课程号', entry.courseNumber),
            DetailRow('时间', entry.slotLabel),
            DetailRow('起止', _clockRange(entry)),
            DetailRow(
              '周次',
              entry.weekName.isNotEmpty
                  ? entry.weekName
                  : entry.weeks.isEmpty
                  ? '尚未公布'
                  : entry.weeks.join('、'),
            ),
            DetailRow('地点', entry.teachingPlace),
            DetailRow('教师', entry.teacherName),
            if (conflicts.isNotEmpty)
              DetailRow(
                '重叠课程',
                conflicts
                    .map((other) => '${other.courseName} · ${other.slotLabel}')
                    .join('\n'),
                icon: Icons.warning_amber_rounded,
              ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = conflicts.isNotEmpty ? scheme.error : _accentFor(entry);
    final bg = accent.withValues(alpha: dark ? 0.22 : 0.12);
    final fg = dark ? Colors.white.withValues(alpha: 0.94) : accent;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: conflicts.isNotEmpty
              ? scheme.error
              : accent.withValues(alpha: dark ? 0.35 : 0.25),
          width: conflicts.isNotEmpty ? 1.4 : 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _details(context),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3.5,
              child: ColoredBox(color: accent),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                (compact ? 8 : 12) + 3.5,
                compact ? 8 : 10,
                compact ? 8 : 12,
                compact ? 8 : 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (conflicts.isNotEmpty) ...[
                    Text(
                      '时间重叠',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    entry.courseName,
                    maxLines: compact ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.hasSlot ? entry.slotLabel : '时间待公布',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: compact ? 11 : 12,
                      color: fg.withValues(alpha: 0.85),
                    ),
                  ),
                  if (entry.teachingPlace.isNotEmpty)
                    Text(
                      entry.teachingPlace,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: compact ? 11 : 12,
                        color: fg.withValues(alpha: 0.85),
                      ),
                    ),
                  if (!compact && entry.teacherName.isNotEmpty)
                    Text(
                      entry.teacherName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: fg.withValues(alpha: 0.78),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _clockRange(ScheduleEntry entry) => [
  if (entry.startTime.isNotEmpty) entry.startTime,
  if (entry.endTime.isNotEmpty) entry.endTime,
].join('–');
