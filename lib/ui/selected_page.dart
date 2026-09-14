/// 我的 hub: 已选课程, 我的课表, 落选课程, and 退选日志.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/models.dart';
import '../data/notifications.dart';
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
      // Header row
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
        child: Row(
          children: [
            Text(
              '我的',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => _refreshAll(ref),
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
            ),
          ],
        ),
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
          for (final tc in list) {
            items.add(_SelectedCard(tc: tc));
            items.add(const SizedBox(height: 10));
          }
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
          for (final entry in list) {
            items.add(_ScheduleCard(entry: entry));
            items.add(const SizedBox(height: 8));
          }
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
        for (final entry in list) {
          items.add(_UnsuccessfulCard(entry: entry));
          items.add(const SizedBox(height: 8));
        }
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
        for (final entry in list) {
          items.add(_LogCard(entry: entry));
          items.add(const SizedBox(height: 6));
        }
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
    return Card(
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
                OutlinedButton.icon(
                  onPressed: _dropping ? null : _confirmDrop,
                  icon: _dropping
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.remove_circle_outline,
                          size: 18, color: scheme.error),
                  label: Text('退选', style: TextStyle(color: scheme.error)),
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

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.entry});
  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Text(e.courseName,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            // Meta row 1
            _meta(e.courseIndex, scheme),
            const SizedBox(height: 4),
            // Meta row 2
            _meta(e.teacherName, scheme),
            // Teaching place (may be empty for unarranged)
            if (e.teachingPlace.isNotEmpty && e.teacherName.isNotEmpty)
              const SizedBox(height: 4),
            if (e.teachingPlace.isNotEmpty) _meta(e.teachingPlace, scheme),
            // Credit / hours
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
                    const Spacer(),
                    if (e.isUnarranged)
                      Text('未排课',
                          style: TextStyle(fontSize: 11, color: scheme.error)),
                  ],
                ),
              ),
            // Exam time when present
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

  Widget _meta(String text, ColorScheme scheme) {
    return Text(text,
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant));
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
