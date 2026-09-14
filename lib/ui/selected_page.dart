/// 我的 hub: 已选课程, 我的课表, 落选课程, and 退选日志.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import 'layout.dart';
import 'widgets.dart';

/// Loads selected courses for the active session.
final selectedCoursesProvider =
    FutureProvider.autoDispose<List<TeachingClass>>((ref) async {
  ref.watch(selectionDataRevisionProvider);
  final session = ref.watch(sessionProvider);
  final student = session.student;
  final batch = session.activeBatch;
  if (student == null || batch == null) return [];
  final course = ref.read(courseServiceProvider);
  return course.fetchSelected(
      studentCode: student.studentCode, batchCode: batch.code);
});

/// Loads the full schedule (arranged + unarranged) for the active session.
final scheduleProvider =
    FutureProvider.autoDispose<List<ScheduleEntry>>((ref) async {
  ref.watch(selectionDataRevisionProvider);
  final session = ref.watch(sessionProvider);
  final student = session.student;
  final batch = session.activeBatch;
  if (student == null || batch == null) return [];
  final course = ref.read(courseServiceProvider);
  final results = await Future.wait([
    course.fetchSchedule(
        studentCode: student.studentCode, batchCode: batch.code),
    course.fetchUnarranged(
        studentCode: student.studentCode, batchCode: batch.code),
  ]);
  return [...results[0], ...results[1]];
});

/// Loads unsuccessful selection entries for the active session.
final unsuccessfulProvider =
    FutureProvider.autoDispose<List<UnsuccessfulEntry>>((ref) async {
  ref.watch(selectionDataRevisionProvider);
  final session = ref.watch(sessionProvider);
  final student = session.student;
  final batch = session.activeBatch;
  if (student == null || batch == null) return [];
  final course = ref.read(courseServiceProvider);
  return course.fetchUnsuccessful(
      studentCode: student.studentCode, batchCode: batch.code);
});

/// Loads drop-log (return-results) entries for the active session.
final returnResultsProvider =
    FutureProvider.autoDispose<List<DropLogEntry>>((ref) async {
  ref.watch(selectionDataRevisionProvider);
  final session = ref.watch(sessionProvider);
  final student = session.student;
  final batch = session.activeBatch;
  if (student == null || batch == null) return [];
  final course = ref.read(courseServiceProvider);
  return course.fetchReturnResults(
      studentCode: student.studentCode, batchCode: batch.code);
});

class SelectedPage extends ConsumerWidget {
  const SelectedPage({super.key});

  Future<void> _refreshAll(WidgetRef ref) async {
    // Each section renders its own error state, so a failed refresh must not
    // escape as an unhandled error from RefreshIndicator.
    final refreshes = <Future<Object?>>[
      ref.refresh(selectedCoursesProvider.future),
      ref.refresh(scheduleProvider.future),
      ref.refresh(unsuccessfulProvider.future),
      ref.refresh(returnResultsProvider.future),
    ];
    await Future.wait<void>([
      for (final f in refreshes) f.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAsync = ref.watch(selectedCoursesProvider);
    final scheduleAsync = ref.watch(scheduleProvider);
    final unsuccessfulAsync = ref.watch(unsuccessfulProvider);
    final returnAsync = ref.watch(returnResultsProvider);

    final items = <Widget>[
      PageHeader(
        title: '我的',
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
        actions: [
          IconButton(
            onPressed: () => _refreshAll(ref),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      const SizedBox(height: 4),

      // ── Section 1: 已选课程 ──
      _SectionHeader(
        icon: Icons.checklist,
        title: '已选课程',
        onRefresh: () => ref.invalidate(selectedCoursesProvider),
      ),
    ];

    selectedAsync.when(
      loading: () =>
          items.add(const Center(child: CircularProgressIndicator())),
      error: (e, _) => items.add(
          EmptyState(icon: Icons.cloud_off, title: '加载失败', subtitle: '$e')),
      data: (list) {
        if (list.isEmpty) {
          items.add(const EmptyState(
            icon: Icons.checklist,
            title: '还没有已选课程',
            subtitle: '在「选课」页选课后会显示在这里。',
          ));
        } else {
          items.add(AdaptiveGrid(
            minColumnWidth: 400,
            maxColumns: 3,
            spacing: 10,
            runSpacing: 10,
            children: [for (final tc in list) _SelectedCard(tc: tc)],
          ));
          items.add(const SizedBox(height: 10));
        }
      },
    );

    // ── Section 2: 我的课表 ──
    items.add(const SizedBox(height: 12));
    items.add(_SectionHeader(
      icon: Icons.calendar_month,
      title: '我的课表',
      onRefresh: () => ref.invalidate(scheduleProvider),
    ));
    scheduleAsync.when(
      loading: () =>
          items.add(const Center(child: CircularProgressIndicator())),
      error: (e, _) => items.add(
          EmptyState(icon: Icons.cloud_off, title: '课表加载失败', subtitle: '$e')),
      data: (list) {
        if (list.isEmpty) {
          items.add(
              const EmptyState(icon: Icons.calendar_month, title: '还没有课表数据'));
        } else {
          items.add(AdaptiveGrid(
            minColumnWidth: 360,
            maxColumns: 3,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final group in _groupSchedule(list))
                _ScheduleCard(group: group),
            ],
          ));
          items.add(const SizedBox(height: 8));
        }
      },
    );

    // ── Section 3: 落选课程 (hidden when empty) ──
    unsuccessfulAsync.when(
      loading: () {
        items.add(const SizedBox(height: 12));
        items.add(_SectionHeader(
          icon: Icons.error_outline,
          title: '落选课程',
          onRefresh: () => ref.invalidate(unsuccessfulProvider),
        ));
        items.add(const Center(child: CircularProgressIndicator()));
      },
      error: (e, _) {
        items.add(const SizedBox(height: 12));
        items.add(_SectionHeader(
          icon: Icons.error_outline,
          title: '落选课程',
          onRefresh: () => ref.invalidate(unsuccessfulProvider),
        ));
        items.add(
            EmptyState(icon: Icons.cloud_off, title: '加载失败', subtitle: '$e'));
      },
      data: (list) {
        if (list.isEmpty) return;
        items.add(const SizedBox(height: 12));
        items.add(_SectionHeader(
          icon: Icons.error_outline,
          title: '落选课程',
          onRefresh: () => ref.invalidate(unsuccessfulProvider),
        ));
        items.add(AdaptiveGrid(
          minColumnWidth: 360,
          maxColumns: 3,
          spacing: 8,
          runSpacing: 8,
          children: [for (final entry in list) _UnsuccessfulCard(entry: entry)],
        ));
        items.add(const SizedBox(height: 8));
      },
    );

    // ── Section 4: 退选日志 (hidden when empty) ──
    returnAsync.when(
      loading: () {
        items.add(const SizedBox(height: 12));
        items.add(_SectionHeader(
          icon: Icons.history,
          title: '退选日志',
          onRefresh: () => ref.invalidate(returnResultsProvider),
        ));
        items.add(const Center(child: CircularProgressIndicator()));
      },
      error: (e, _) {
        items.add(const SizedBox(height: 12));
        items.add(_SectionHeader(
          icon: Icons.history,
          title: '退选日志',
          onRefresh: () => ref.invalidate(returnResultsProvider),
        ));
        items.add(
            EmptyState(icon: Icons.cloud_off, title: '加载失败', subtitle: '$e'));
      },
      data: (list) {
        if (list.isEmpty) return;
        items.add(const SizedBox(height: 12));
        items.add(_SectionHeader(
          icon: Icons.history,
          title: '退选日志',
          onRefresh: () => ref.invalidate(returnResultsProvider),
        ));
        items.add(AdaptiveGrid(
          minColumnWidth: 340,
          maxColumns: 3,
          spacing: 6,
          runSpacing: 6,
          children: [for (final entry in list) _LogCard(entry: entry)],
        ));
        items.add(const SizedBox(height: 6));
      },
    );

    return RefreshIndicator(
      onRefresh: () => _refreshAll(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: items,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.onRefresh,
  });

  final IconData icon;
  final String title;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selected course card (kept as-is)
// ---------------------------------------------------------------------------

class _SelectedCard extends ConsumerStatefulWidget {
  const _SelectedCard({required this.tc});
  final TeachingClass tc;

  @override
  ConsumerState<_SelectedCard> createState() => _SelectedCardState();
}

class _SelectedCardState extends ConsumerState<_SelectedCard> {
  bool _dropping = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tc = widget.tc;
    final batch = ref.watch(sessionProvider.select((s) => s.activeBatch));
    // The server marks selections from other rounds canDelete="0", and a
    // 选后不可退 round (tacticCode 02) disables dropping altogether. Show the
    // state instead of letting the request bounce.
    final roundAllows = batch?.allowsDrop ?? true;
    final canDrop = tc.canDelete && roundAllows;
    final dropHint = !roundAllows
        ? '本轮次选后不可退'
        : !tc.canDelete
            ? '非本轮次所选，本轮不可退'
            : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tc.courseName,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(tc.displayTitle,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            if (tc.teachingPlace.isNotEmpty)
              Text(tc.teachingPlace,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              children: [
                const StatusPill(
                    label: '已选', color: Colors.green, icon: Icons.check),
                const Spacer(),
                Tooltip(
                  message: dropHint ?? '',
                  child: OutlinedButton.icon(
                    onPressed: _dropping || !canDrop ? null : _confirmDrop,
                    icon: _dropping
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.remove_circle_outline,
                            size: 18, color: canDrop ? scheme.error : null),
                    label: Text(canDrop ? '退选' : '本轮不可退',
                        style: TextStyle(color: canDrop ? scheme.error : null)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDrop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退选'),
        content: Text('确定要退选「${widget.tc.courseName}」吗？此操作会真实改变你的选课状态。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认退选')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _dropping = true);
    try {
      final session = ref.read(sessionProvider);
      final enroll = ref.read(enrollServiceProvider);
      final outcome = await enroll.dropCourse(
        teachingClassId: widget.tc.teachingClassId,
        studentCode: session.student!.studentCode,
        batchCode: session.activeBatch!.code,
      );
      if (!mounted) return;
      showToast(context, outcome.message, success: outcome.success);
      if (outcome.success) {
        ref.read(selectionDataRevisionProvider.notifier).state++;
        NotificationService.instance.dropped(
          courseName: widget.tc.courseName,
          className: widget.tc.displayTitle,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, '$e', success: false);
    } finally {
      if (mounted) setState(() => _dropping = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Schedule entry card
// ---------------------------------------------------------------------------

/// teachingTime.do returns one row per (class, weekday, week pattern), so a
/// two-slot course arrives as several near-identical rows. Group them by
/// teaching class and show each slot on its own line, like a timetable.
class _ScheduleGroup {
  _ScheduleGroup(this.first);
  final ScheduleEntry first;
  final List<ScheduleEntry> slots = [];
}

List<_ScheduleGroup> _groupSchedule(List<ScheduleEntry> entries) {
  final groups = <String, _ScheduleGroup>{};
  for (final e in entries) {
    final key = e.teachingClassId.isNotEmpty
        ? e.teachingClassId
        : '${e.courseNumber}:${e.courseIndex}';
    final g = groups.putIfAbsent(key, () => _ScheduleGroup(e));
    if (e.hasSlot) g.slots.add(e);
  }
  for (final g in groups.values) {
    g.slots.sort((a, b) {
      final d = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (d != 0) return d;
      final sec = a.beginSection.compareTo(b.beginSection);
      if (sec != 0) return sec;
      return a.weeks.isEmpty || b.weeks.isEmpty
          ? 0
          : a.weeks.first.compareTo(b.weeks.first);
    });
  }
  return groups.values.toList();
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.group});
  final _ScheduleGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = group.first;
    final meta = [
      if (e.courseIndex.isNotEmpty) '[${e.courseIndex}]',
      if (e.teacherName.isNotEmpty) e.teacherName,
    ].join(' ');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.courseName,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(meta,
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            if (group.slots.isEmpty)
              Row(
                children: [
                  Icon(Icons.schedule, size: 15, color: scheme.error),
                  const SizedBox(width: 6),
                  Text(e.isUnarranged ? '未排课' : '时间待定',
                      style: TextStyle(fontSize: 12, color: scheme.error)),
                ],
              )
            else
              for (final slot in group.slots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.schedule,
                          size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [
                            slot.slotLabel,
                            if (slot.weekName.isNotEmpty) slot.weekName,
                            if (slot.teachingPlace.isNotEmpty)
                              slot.teachingPlace,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            if (e.credit.isNotEmpty || e.hours.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    if (e.credit.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('${e.credit}学分',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onPrimaryContainer)),
                      ),
                    if (e.credit.isNotEmpty && e.hours.isNotEmpty)
                      const SizedBox(width: 6),
                    if (e.hours.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('${e.hours}学时',
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSecondaryContainer)),
                      ),
                  ],
                ),
              ),
            if (e.examTime.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('考试: ${e.examTime}',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unsuccessful card
// ---------------------------------------------------------------------------

class _UnsuccessfulCard extends StatelessWidget {
  const _UnsuccessfulCard({required this.entry});
  final UnsuccessfulEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.courseName,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (e.teacherName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(e.teacherName,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
              ),
            if (e.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(e.reason,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onErrorContainer)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drop-log compact row
// ---------------------------------------------------------------------------

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});
  final DropLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.courseName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '${e.deleteOperateTypeName.isNotEmpty ? '${e.deleteOperateTypeName} · ' : ''}${e.deleteOperateTime}',
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
