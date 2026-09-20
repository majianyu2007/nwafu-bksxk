/// 我的: 已选课程 (with textbook actions), 课表, 落选课程, 退选日志.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import '../data/param_builders.dart';
import 'courses_page.dart';
import 'layout.dart';
import 'weekly_timetable.dart';
import 'widgets.dart';

/// Loads selected courses for the shown account.
final selectedCoursesProvider =
    FutureProvider.autoDispose<List<TeachingClass>>((ref) async {
  ref.watch(currentSelectionRevisionProvider);
  final session = ref.watch(sessionProvider);
  final student = session.student;
  final batch = session.activeBatch;
  if (student == null || batch == null) return [];
  return ref.read(courseServiceProvider).fetchSelected(
        studentCode: student.studentCode,
        batchCode: batch.code,
        volunteerRound: batch.isVolunteerRound,
      );
});

/// Loads the full schedule (arranged + unarranged).
final scheduleProvider =
    FutureProvider.autoDispose<List<ScheduleEntry>>((ref) async {
  ref.watch(currentSelectionRevisionProvider);
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

/// The whole 落选 list (isRead=1), as the official sidebar shows it.
final unsuccessfulProvider =
    FutureProvider.autoDispose<List<UnsuccessfulEntry>>((ref) async {
  ref.watch(currentSelectionRevisionProvider);
  final session = ref.watch(sessionProvider);
  final student = session.student;
  final batch = session.activeBatch;
  if (student == null || batch == null) return [];
  return ref.read(courseServiceProvider).fetchUnsuccessful(
      studentCode: student.studentCode, batchCode: batch.code, isRead: true);
});

final returnResultsProvider =
    FutureProvider.autoDispose<List<DropLogEntry>>((ref) async {
  ref.watch(currentSelectionRevisionProvider);
  final session = ref.watch(sessionProvider);
  final student = session.student;
  final batch = session.activeBatch;
  if (student == null || batch == null) return [];
  return ref.read(courseServiceProvider).fetchReturnResults(
      studentCode: student.studentCode, batchCode: batch.code);
});

class SelectedPage extends ConsumerWidget {
  const SelectedPage({super.key});

  Future<void> _refreshAll(WidgetRef ref) async {
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
    final batch = ref.watch(sessionProvider.select((s) => s.activeBatch));
    final scheduleAsync = ref.watch(scheduleProvider);
    final unsuccessfulAsync = ref.watch(unsuccessfulProvider);
    final returnAsync = ref.watch(returnResultsProvider);
    final volunteer = batch?.isVolunteerRound == true;

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
      _SectionHeader(
        icon: Icons.checklist,
        title: volunteer ? '已填报志愿' : '已选课程',
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
          items.add(EmptyState(
            icon: Icons.checklist,
            title: volunteer ? '还没有填报志愿' : '还没有已选课程',
          ));
        } else {
          final credits = list.fold<double>(
              0, (n, tc) => n + (double.tryParse(tc.credit) ?? 0));
          items.add(Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              '${list.length} 门，共 ${credits == credits.roundToDouble() ? credits.toStringAsFixed(0) : credits.toStringAsFixed(1)} 学分',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ));
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

    items.add(const SizedBox(height: 12));
    items.add(_SectionHeader(
      icon: Icons.calendar_month,
      title: '课表',
      onRefresh: () => ref.invalidate(scheduleProvider),
    ));
    scheduleAsync.when(
      loading: () =>
          items.add(const Center(child: CircularProgressIndicator())),
      error: (e, _) => items.add(
          EmptyState(icon: Icons.cloud_off, title: '课表加载失败', subtitle: '$e')),
      data: (list) {
        if (list.isEmpty) {
          items.add(const EmptyState(icon: Icons.calendar_month, title: '还没有课表'));
        } else {
          items.add(WeeklyTimetable(entries: list));
          items.add(const SizedBox(height: 8));
        }
      },
    );

    void section(String title, IconData icon, VoidCallback onRefresh,
        AsyncValue<List<Object>> async, Widget Function(List<Object>) body) {
      async.when(
        loading: () {
          items.add(const SizedBox(height: 12));
          items.add(_SectionHeader(icon: icon, title: title, onRefresh: onRefresh));
          items.add(const Center(child: CircularProgressIndicator()));
        },
        error: (e, _) {
          items.add(const SizedBox(height: 12));
          items.add(_SectionHeader(icon: icon, title: title, onRefresh: onRefresh));
          items.add(EmptyState(icon: Icons.cloud_off, title: '加载失败', subtitle: '$e'));
        },
        data: (list) {
          if (list.isEmpty) return;
          items.add(const SizedBox(height: 12));
          items.add(_SectionHeader(icon: icon, title: title, onRefresh: onRefresh));
          items.add(body(list));
          items.add(const SizedBox(height: 8));
        },
      );
    }

    section(
      '落选课程',
      Icons.error_outline,
      () => ref.invalidate(unsuccessfulProvider),
      unsuccessfulAsync,
      (list) => AdaptiveGrid(
        minColumnWidth: 360,
        maxColumns: 3,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in list.cast<UnsuccessfulEntry>()) _UnsuccessfulCard(entry: e)
        ],
      ),
    );
    section(
      '退选记录',
      Icons.history,
      () => ref.invalidate(returnResultsProvider),
      returnAsync,
      (list) => AdaptiveGrid(
        minColumnWidth: 340,
        maxColumns: 3,
        spacing: 6,
        runSpacing: 6,
        children: [for (final e in list.cast<DropLogEntry>()) _LogCard(entry: e)],
      ),
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

class _SelectedCard extends ConsumerStatefulWidget {
  const _SelectedCard({required this.tc});
  final TeachingClass tc;

  @override
  ConsumerState<_SelectedCard> createState() => _SelectedCardState();
}

class _SelectedCardState extends ConsumerState<_SelectedCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tc = widget.tc;
    final batch = ref.watch(sessionProvider.select((s) => s.activeBatch));
    final volunteer = batch?.isVolunteerRound == true;
    // The server marks selections from other rounds canDelete="0", and a
    // 选后不可退 round (tacticCode 02) disables dropping altogether.
    final roundAllows = batch?.allowsDrop ?? true;
    final canDrop = tc.canDelete && roundAllows;
    final dropHint = !roundAllows
        ? '本轮次选后不可退'
        : !tc.canDelete
            ? '非本轮次所选'
            : null;
    // Textbook buttons follow the official 已选课程 panel: 订购 when the round
    // allows ordering and the class has textbooks; 退订 when the round allows
    // cancelling and there is something ordered.
    final canOrderBook = (batch?.canSelectBook ?? false) && tc.hasBook;
    final canCancelBook = (batch?.canDeleteBook ?? false) &&
        (tc.hasBook || tc.needBook == '1' || tc.needBook == '5');
    final meta = [
      if (tc.credit.isNotEmpty) '${tc.credit} 学分',
      if (tc.hours.isNotEmpty) '${tc.hours} 学时',
      if (tc.courseTypeName.isNotEmpty) tc.courseTypeName,
      if (tc.publicCourseType.isNotEmpty) tc.publicCourseType,
      if (tc.hasBook) '教材${tc.textbookStateLabel}',
    ].join('  ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tc.courseName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                StatusPill(
                    label: volunteer && tc.heldVolunteerGrade.isNotEmpty
                        ? '第${tc.heldVolunteerGrade}志愿'
                        : '已选',
                    color: Colors.green,
                    icon: Icons.check),
              ],
            ),
            const SizedBox(height: 4),
            Text(tc.displayTitle,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            Text(
              tc.teachingPlace.isNotEmpty
                  ? tc.teachingPlace
                  : tc.onlinePlatform.isNotEmpty
                      ? '${tc.onlinePlatform} 网课'
                      : '',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            if (meta.isNotEmpty)
              Text(meta,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            if (tc.isConflict && tc.conflictDesc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tc.conflictDesc,
                    style: TextStyle(color: scheme.error, fontSize: 12)),
              ),
            if (volunteer && tc.hasCapacityInfo) ...[
              const SizedBox(height: 10),
              CapacityBar(
                selected: tc.firstVolunteers,
                capacity: tc.classCapacity,
                label: '第一志愿',
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (canOrderBook)
                  OutlinedButton(
                    onPressed: _busy ? null : _orderBooks,
                    child: const Text('订购教材'),
                  ),
                if (canCancelBook)
                  OutlinedButton(
                    onPressed: _busy ? null : _cancelBooks,
                    child: const Text('退订教材'),
                  ),
                Tooltip(
                  message: dropHint ?? '',
                  child: OutlinedButton.icon(
                    onPressed: _busy || !canDrop ? null : _confirmDrop,
                    icon: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.remove_circle_outline,
                            size: 18, color: canDrop ? scheme.error : null),
                    label: Text(canDrop ? '退选' : (dropHint ?? '不可退'),
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
        title: const Text('退选'),
        content: Text('确定退选「${widget.tc.courseName}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退选')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
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
        bumpCurrentSelectionRevision(ref);
        NotificationService.instance.dropped(
          courseName: widget.tc.courseName,
          className: widget.tc.displayTitle,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, '$e', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _orderBooks() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('订购教材'),
        content: Text('订购「${widget.tc.courseName}」的教材？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('订购')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(sessionProvider);
      final res = await ref.read(courseServiceProvider).orderTextbooks(
            studentCode: session.student!.studentCode,
            batchCode: session.activeBatch!.code,
            teachingClassId: widget.tc.teachingClassId,
          );
      if (!mounted) return;
      showToast(context, res.ok ? '已订购教材' : (res.msg.isEmpty ? '订购失败' : res.msg),
          success: res.ok);
      if (res.ok) bumpCurrentSelectionRevision(ref);
    } catch (e) {
      if (mounted) showToast(context, '$e', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 退订: the official dialog lists the ordered books and lets the student
  /// pick which to cancel, with a reason each; modifybook.do czlx=0.
  Future<void> _cancelBooks() async {
    final session = ref.read(sessionProvider);
    final student = session.student!;
    final batch = session.activeBatch!;
    setState(() => _busy = true);
    try {
      final course = ref.read(courseServiceProvider);
      final results = await Future.wait([
        course.fetchTextbookOptions(
          studentCode: student.studentCode,
          batchCode: batch.code,
          teachingClassId: widget.tc.teachingClassId,
        ),
        ref.read(infoServiceProvider).fetchTextbookReasons(),
      ]);
      final reasons = results[1] as List<TextbookReason>;
      final options = [
        for (final o in results[0] as List<TextbookOption>)
          if (o.ordered) o.copyWith(reasonCodes: reasons),
      ];
      if (!mounted) return;
      if (options.isEmpty) {
        showToast(context, '没有已订购的教材');
        return;
      }
      final selection = await showAdaptiveSheet<TextbookSelection>(
        context,
        scrollControlled: true,
        builder: (context) => TextbookPicker(options: options, title: '退订教材'),
      );
      if (selection == null || !mounted) return;
      // Only declined books (bookCode-reason) are sent for a cancellation.
      final declined = selection.choices.where((c) => !c.order).toList();
      if (declined.isEmpty) {
        showToast(context, '没有选择要退订的教材');
        return;
      }
      final res = await course.modifyTextbooks(
        studentCode: student.studentCode,
        batchCode: batch.code,
        teachingClassId: widget.tc.teachingClassId,
        jcxx: buildBookSelection(declined),
        cancel: true,
      );
      if (!mounted) return;
      showToast(context, res.ok ? '已退订教材' : (res.msg.isEmpty ? '退订失败' : res.msg),
          success: res.ok);
      if (res.ok) bumpCurrentSelectionRevision(ref);
    } catch (e) {
      if (mounted) showToast(context, '$e', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.displayTitle,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (e.teacherName.isNotEmpty) e.teacherName,
                      if (e.time.length >= 10) e.time.substring(0, 10),
                      if (e.credit.isNotEmpty) '${e.credit} 学分',
                    ].join('  '),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(label: e.reason.isEmpty ? '落选' : e.reason, color: scheme.error),
          ],
        ),
      ),
    );
  }
}

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${e.courseName}${e.courseIndex.isNotEmpty ? '[${e.courseIndex}]' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 2),
            Text(
              [
                if (e.teacherName.isNotEmpty) e.teacherName,
                if (e.deleteOperateTypeName.isNotEmpty) e.deleteOperateTypeName,
                e.deleteOperateTime,
              ].where((s) => s.isNotEmpty).join('  '),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
