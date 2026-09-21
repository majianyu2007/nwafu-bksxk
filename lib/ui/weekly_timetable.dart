/// A date-aware timetable. Calendar calibration is independent of course rows;
/// a course that starts later in the term must never move the current week.
library;

import 'package:flutter/material.dart';

import '../data/academic_calendar.dart';
import '../data/models.dart';
import 'layout.dart';
import 'widgets.dart';

const _dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

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
    final blocks = widget.entries
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
            ? '当前第 $currentWeek 周'
            : calendar.hasNotStarted(widget.today)
                ? '学期尚未开始'
                : '已超出已设学期周数';

    Widget course(ScheduleEntry entry, {bool compact = false}) => _CourseBlock(
          entry: entry,
          compact: compact,
          conflicts: conflicts[entry] ?? const [],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.term.label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(status, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                calendar?.sourceLabel ?? '请校准本学期教学周；未校准时仅浏览周次，不推测当前周。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '上一周',
                        onPressed: week > 1
                            ? () => setState(() => _browsingWeek = week - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      DropdownButton<int>(
                        value: week,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (var w = 1; w <= maxWeek; w++)
                            DropdownMenuItem(value: w, child: Text('第 $w 周')),
                        ],
                        onChanged: (value) =>
                            setState(() => _browsingWeek = value),
                      ),
                      IconButton(
                        tooltip: '下一周',
                        onPressed: week < maxWeek
                            ? () => setState(() => _browsingWeek = week + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: currentWeek == null || _browsingWeek == null
                        ? null
                        : () => setState(() => _browsingWeek = null),
                    icon: const Icon(Icons.today_outlined, size: 18),
                    label: const Text('回到本周'),
                  ),
                  TextButton.icon(
                    onPressed: widget.onCalibrate,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('校准教学周'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${monday == null ? '浏览第 $week 周' : '${_date(monday)} — ${_date(monday.add(const Duration(days: 6)))}'} · ${blocks.length} 次课程',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          NoticeStrip(
            text: '${conflicts.length} 次课程存在时间重叠，已逐一列出；点按课程查看冲突详情。',
            icon: Icons.warning_amber_rounded,
            error: true,
            margin: EdgeInsets.zero,
          ),
        ],
        const SizedBox(height: 12),
        if (blocks.isEmpty)
          const EmptyState(
            icon: Icons.event_available_outlined,
            title: '本周没有已排课程',
            subtitle: '可切换周次查看其他周的安排',
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            // A seven-day grid becomes unreadable with narrow columns or large
            // accessibility text. Switch to the same blocks in a day agenda.
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth < 1000 || scale > 1.3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var day = 1; day <= 7; day++)
                    if (blocks.any((entry) => entry.dayOfWeek == day)) ...[
                      _DayHeader(
                        day: day,
                        date: monday?.add(Duration(days: day - 1)),
                        today: widget.today,
                      ),
                      const SizedBox(height: 8),
                      for (final entry in blocks)
                        if (entry.dayOfWeek == day)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: course(entry),
                          ),
                      const SizedBox(height: 8),
                    ],
                ],
              );
            }
            return _WeekGrid(
              blocks: blocks,
              monday: monday,
              today: widget.today,
              course: (entry) => course(entry, compact: true),
            );
          }),
        if (unscheduled.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('待公布时间 / 周次', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in unscheduled)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: course(entry),
            ),
        ],
      ],
    );
  }
}

String _date(DateTime date) => '${date.year}/${date.month}/${date.day}';

class _DayHeader extends StatelessWidget {
  const _DayHeader(
      {required this.day, required this.date, required this.today});
  final int day;
  final DateTime? date;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = date == calendarDate(today);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isToday ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${_dayNames[day - 1]}${date == null ? '' : ' ${date!.month}/${date!.day}'}${isToday ? ' · 今天' : ''}',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: isToday ? scheme.onPrimaryContainer : scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.blocks,
    required this.monday,
    required this.today,
    required this.course,
  });
  final List<ScheduleEntry> blocks;
  final DateTime? monday;
  final DateTime today;
  final Widget Function(ScheduleEntry) course;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Rows grow with their content, so overlapping courses never paint on top
    // of one another and long names / text scaling cannot overflow a slot.
    return Table(
      columnWidths: const {0: FixedColumnWidth(44)},
      border: TableBorder.all(color: scheme.outlineVariant),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(children: [
          const SizedBox.shrink(),
          for (var day = 1; day <= 7; day++)
            Padding(
              padding: const EdgeInsets.all(4),
              child: _DayHeader(
                day: day,
                date: monday?.add(Duration(days: day - 1)),
                today: today,
              ),
            ),
        ]),
        for (final period in const [
          (label: '上午', begin: 1, end: 4),
          (label: '下午', begin: 5, end: 8),
          (label: '晚上', begin: 9, end: 1000),
        ])
          TableRow(
            decoration: BoxDecoration(color: scheme.surfaceContainerLowest),
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Text(period.label,
                    style: Theme.of(context).textTheme.labelMedium),
              ),
              for (var day = 1; day <= 7; day++)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      for (final entry in blocks)
                        if (entry.dayOfWeek == day &&
                            entry.beginSection >= period.begin &&
                            entry.beginSection <= period.end)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: course(entry),
                          ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
            ],
          ),
      ],
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
                Text(entry.courseName,
                    style: Theme.of(context).textTheme.titleLarge),
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
                            : entry.weeks.join('、')),
                DetailRow('地点', entry.teachingPlace),
                DetailRow('教师', entry.teacherName),
                if (conflicts.isNotEmpty)
                  DetailRow(
                      '重叠课程',
                      conflicts
                          .map((other) =>
                              '${other.courseName} · ${other.slotLabel}')
                          .join('\n'),
                      icon: Icons.warning_amber_rounded),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
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
    final key = entry.teachingClassId.isNotEmpty
        ? entry.teachingClassId
        : entry.courseName;
    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    final colors = [
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];
    final (background, foreground) = colors[hash % colors.length];
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: conflicts.isEmpty ? Colors.transparent : scheme.error,
          width: conflicts.isEmpty ? 0 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _details(context),
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (conflicts.isNotEmpty) ...[
                Text('时间重叠',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: foreground, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
              ],
              Text(entry.courseName,
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(entry.hasSlot ? entry.slotLabel : '时间待公布',
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: foreground)),
              if (_clockRange(entry).isNotEmpty)
                Text(_clockRange(entry),
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: foreground)),
              if (entry.teachingPlace.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(entry.teachingPlace,
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: foreground)),
              ],
              if (entry.teacherName.isNotEmpty)
                Text(entry.teacherName,
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: foreground)),
              if (entry.hasSlot && entry.weeks.isEmpty)
                Text('周次待公布',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

String _clockRange(ScheduleEntry entry) => [
      if (entry.startTime.isNotEmpty) entry.startTime,
      if (entry.endTime.isNotEmpty) entry.endTime,
    ].join('–');
