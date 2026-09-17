/// Weekly timetable built from teachingTime.do / noArranged.do rows.
///
/// The server returns one row per (teaching class, weekday, week pattern) with
/// `dayOfWeek`, `beginSection`/`endSection`, a `week` bit string and the room.
/// This widget renders the classic university grid: sections down, weekdays
/// across, one column per day, with a week picker so the student sees exactly
/// what is taught in a given week (single/double-week courses differ).
library;

import 'package:flutter/material.dart';

import '../data/models.dart';

/// Sections per day on this campus (batch.do morning 1-4, afternoon 5-8,
/// night 9-11). Start times mirror what the server returns in `startTime`.
const int kSectionsPerDay = 11;
const List<String> _kSectionTimes = [
  '08:00',
  '08:55',
  '10:10',
  '11:05',
  '14:30',
  '15:25',
  '16:30',
  '17:25',
  '19:30',
  '20:25',
  '21:20',
];
const List<String> _kDayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// One placed block in the grid.
class TimetableBlock {
  TimetableBlock({
    required this.entry,
    required this.day,
    required this.begin,
    required this.end,
  });
  final ScheduleEntry entry;
  final int day; // 1..7
  final int begin; // 1..11
  final int end; // >= begin
}

class WeeklyTimetable extends StatefulWidget {
  const WeeklyTimetable({super.key, required this.entries});
  final List<ScheduleEntry> entries;

  @override
  State<WeeklyTimetable> createState() => _WeeklyTimetableState();
}

class _WeeklyTimetableState extends State<WeeklyTimetable> {
  int? _week;

  /// All week numbers any slot is taught in, sorted; at least 1..18 so the
  /// picker never collapses to nothing.
  List<int> get _weeks {
    final s = <int>{};
    for (final e in widget.entries) {
      s.addAll(e.weeks);
    }
    if (s.isEmpty) return [for (var i = 1; i <= 18; i++) i];
    final max = s.reduce((a, b) => a > b ? a : b);
    return [for (var i = 1; i <= max; i++) i];
  }

  /// The current teaching week guess: the earliest week that still has any
  /// class scheduled on or after today is unknowable without the term start,
  /// so default to the first week that has anything at all.
  int get _defaultWeek {
    for (final e in widget.entries) {
      if (e.weeks.isNotEmpty) return e.weeks.first;
    }
    return 1;
  }

  List<TimetableBlock> _blocksFor(int week) {
    final blocks = <TimetableBlock>[];
    for (final e in widget.entries) {
      if (!e.hasSlot) continue;
      if (!e.weeks.contains(week)) continue;
      blocks.add(TimetableBlock(
        entry: e,
        day: e.dayOfWeek,
        begin: e.beginSection.clamp(1, kSectionsPerDay),
        end: e.endSection.clamp(e.beginSection, kSectionsPerDay),
      ));
    }
    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weeks = _weeks;
    final week = _week ?? _defaultWeek;
    final blocks = _blocksFor(week);
    final unarranged = widget.entries.where((e) => !e.hasSlot).toList();
    // Stable colour per teaching class so the same course keeps its hue.
    final palette = _palette(scheme);
    final colorOf = <String, Color>{};
    for (final e in widget.entries) {
      final k = e.teachingClassId.isNotEmpty ? e.teachingClassId : e.courseName;
      colorOf.putIfAbsent(k, () => palette[colorOf.length % palette.length]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekPicker(
          weeks: weeks,
          selected: week,
          onChanged: (w) => setState(() => _week = w),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          // The grid needs ~90px per day to be legible; scroll sideways on
          // phones instead of squeezing seven columns into 400px.
          const minWidth = 56.0 + 7 * 92.0;
          final width =
              constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth;
          final grid = SizedBox(
            width: width,
            child: _Grid(blocks: blocks, colorOf: colorOf),
          );
          return constraints.maxWidth < minWidth
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: grid)
              : grid;
        }),
        if (unarranged.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('未排课程', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in unarranged)
                Chip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text(
                    '${e.courseName}${e.teacherName.isNotEmpty ? ' · ${e.teacherName}' : ''}',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static List<Color> _palette(ColorScheme scheme) => [
        scheme.primaryContainer,
        scheme.secondaryContainer,
        scheme.tertiaryContainer,
        Colors.orange.withValues(alpha: 0.25),
        Colors.teal.withValues(alpha: 0.25),
        Colors.purple.withValues(alpha: 0.22),
        Colors.pink.withValues(alpha: 0.22),
        Colors.lightGreen.withValues(alpha: 0.28),
        Colors.amber.withValues(alpha: 0.28),
        Colors.indigo.withValues(alpha: 0.22),
      ];
}

class _WeekPicker extends StatelessWidget {
  const _WeekPicker(
      {required this.weeks, required this.selected, required this.onChanged});
  final List<int> weeks;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '上一周',
          onPressed:
              selected > weeks.first ? () => onChanged(selected - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final w in weeks)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text('第$w周'),
                      selected: w == selected,
                      onSelected: (_) => onChanged(w),
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: '下一周',
          onPressed:
              selected < weeks.last ? () => onChanged(selected + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.blocks, required this.colorOf});
  final List<TimetableBlock> blocks;
  final Map<String, Color> colorOf;

  static const double _rowHeight = 64;
  static const double _timeColWidth = 56;
  static const double _headerHeight = 32;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final dayWidth = (constraints.maxWidth - _timeColWidth) / 7;
      const gridHeight = _headerHeight + kSectionsPerDay * _rowHeight;
      return Container(
        height: gridHeight,
        decoration: BoxDecoration(
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background: header row, time column, faint row/column lines.
            Column(
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: _timeColWidth),
                      for (var d = 0; d < 7; d++)
                        SizedBox(
                          width: dayWidth,
                          child: Center(
                            child: Text(_kDayNames[d],
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ),
                    ],
                  ),
                ),
                for (var s = 1; s <= kSectionsPerDay; s++)
                  Container(
                    height: _rowHeight,
                    decoration: BoxDecoration(
                      color: s > 8
                          ? scheme.surfaceContainerLow
                          : (s > 4 ? scheme.surfaceContainerLowest : null),
                      border: Border(
                        top: BorderSide(
                          color: scheme.outlineVariant.withValues(
                              alpha: (s == 5 || s == 9) ? 0.9 : 0.3),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: _timeColWidth,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$s',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                              Text(_kSectionTimes[s - 1],
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        for (var d = 0; d < 7; d++)
                          Container(
                            width: dayWidth,
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                    color: scheme.outlineVariant
                                        .withValues(alpha: 0.3)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            // Blocks.
            for (final b in blocks)
              Positioned(
                left: _timeColWidth + (b.day - 1) * dayWidth + 2,
                top: _headerHeight + (b.begin - 1) * _rowHeight + 2,
                width: dayWidth - 4,
                height: (b.end - b.begin + 1) * _rowHeight - 4,
                child: _BlockTile(
                  block: b,
                  color: colorOf[b.entry.teachingClassId.isNotEmpty
                          ? b.entry.teachingClassId
                          : b.entry.courseName] ??
                      scheme.primaryContainer,
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({required this.block, required this.color});
  final TimetableBlock block;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final e = block.entry;
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      if (e.teachingPlace.isNotEmpty) e.teachingPlace,
      if (e.teacherName.isNotEmpty) e.teacherName,
      if (e.weekName.isNotEmpty) e.weekName,
    ].join('\n');
    return Tooltip(
      message: '${e.courseName}\n${e.slotLabel}\n$detail',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.courseName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  height: 1.2),
            ),
            if (e.teachingPlace.isNotEmpty)
              Text(
                e.teachingPlace,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            if (e.teacherName.isNotEmpty)
              Text(
                e.teacherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
