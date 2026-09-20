/// Monitor page: the shown account's watch list with live status, per-watch
/// controls, a start/stop button, and a rolling activity log. On wide windows
/// the log becomes a side panel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import '../app/providers.dart';
import '../core/constants.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';
import '../data/param_builders.dart';
import 'courses_page.dart';
import 'layout.dart';
import 'widgets.dart';

/// Available width at which the activity log moves beside the watch list.
const double _kSideLogBreakpoint = 1000;

class MonitorPage extends ConsumerWidget {
  const MonitorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watches = ref.watch(watchesProvider);
    final running = ref.watch(monitorRunningProvider);
    final engine = ref.read(monitorEngineProvider);
    final labelOf =
        (ref.watch(sysParamsProvider).asData?.value ?? SysParams.empty).tabName;

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideLog = constraints.maxWidth >= _kSideLogBreakpoint;
        final list = _WatchList(watches: watches, labelOf: labelOf);

        return Column(
          children: [
            PageHeader(
              title: '监控',
              actions: [
                if (watches.isNotEmpty) const _ModeSelector(),
                if (watches.isNotEmpty) const SizedBox(width: 8),
                if (watches.isNotEmpty)
                  FilledButton.icon(
                    onPressed: running ? engine.stop : engine.start,
                    icon: Icon(running ? Icons.stop : Icons.play_arrow),
                    label: Text(running ? '停止' : '开始监控'),
                  ),
              ],
            ),
            const _StatusStrip(),
            Expanded(
              child: sideLog
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: list),
                        const SizedBox(
                          width: 340,
                          child: _ActivityLog(panel: true),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: list),
                        const _ActivityLog(panel: false),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _WatchList extends StatelessWidget {
  const _WatchList({required this.watches, required this.labelOf});
  final List<Watch> watches;
  final String Function(CourseKind) labelOf;

  @override
  Widget build(BuildContext context) {
    if (watches.isEmpty) {
      return const EmptyState(
        icon: Icons.radar,
        title: '还没有监控的课程',
        subtitle: '在「选课」页给教学班点「加入监控」，有人退课时自动补上。',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        AdaptiveGrid(
          minColumnWidth: 380,
          maxColumns: 3,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final w in watches)
              _WatchCard(watch: w, categoryLabel: labelOf(w.kind)),
          ],
        ),
      ],
    );
  }
}

/// One strip that says what the engine is doing: running, waiting for the
/// round to open, or why it stopped on its own.
class _StatusStrip extends ConsumerWidget {
  const _StatusStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(monitorRunningProvider);
    final plan = ref.watch(planStateProvider);
    final engine = ref.read(monitorEngineProvider);
    if (running) {
      final waiting = plan.armed && !plan.batchOpen;
      return NoticeStrip(
        icon: Icons.radar,
        text: waiting
            ? '监控中，等轮次开放后再提交${plan.lastCheckedAt != null ? '（上次检查 ${formatClock(plan.lastCheckedAt!)}）' : ''}'
            : '监控中，发现空位立即提交',
      );
    }
    final reason = engine.stopReason;
    if (reason != null) {
      return NoticeStrip(
          icon: Icons.pause_circle_outline, error: true, text: '已自动停止：$reason');
    }
    if (plan.armed) {
      return const NoticeStrip(
          icon: Icons.schedule, text: '计划模式：开始监控后，等轮次开放再提交');
    }
    return const SizedBox.shrink();
  }
}

class _ModeSelector extends ConsumerWidget {
  const _ModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planStateProvider);
    final id = ref.watch(activeAccountIdProvider);
    if (id == null) return const SizedBox.shrink();
    final controller = ref.read(planControllerOfProvider(id).notifier);
    return PopupMenuButton<String>(
      tooltip: '提交时机',
      onSelected: (value) =>
          value == 'wait' ? controller.arm() : controller.disarm(),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'now',
          child: ListTile(
            leading: Icon(Icons.bolt_outlined),
            title: Text('有空位立即提交'),
          ),
        ),
        PopupMenuItem(
          value: 'wait',
          child: ListTile(
            leading: Icon(Icons.schedule),
            title: Text('等轮次开放再提交'),
          ),
        ),
      ],
      child: Chip(
        avatar:
            Icon(plan.armed ? Icons.schedule : Icons.bolt_outlined, size: 18),
        label: Text(plan.armed ? '等待开放' : '立即提交'),
      ),
    );
  }
}

class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.watch, required this.categoryLabel});
  final Watch watch;
  final String categoryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final engine = ref.read(monitorEngineProvider);
    final tc = watch.teachingClass;
    final (color, label, icon) = _statusVisual(watch.status, scheme);
    final platform = tc.onlinePlatform;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tc.courseName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                StatusPill(label: label, color: color, icon: icon),
              ],
            ),
            const SizedBox(height: 2),
            Text(tc.displayTitle,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            Text(
              tc.teachingPlace.isNotEmpty
                  ? tc.teachingPlace
                  : platform.isNotEmpty
                      ? '$platform 网课'
                      : '',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusPill(label: categoryLabel, color: scheme.secondary),
                if (tc.publicCourseType.isNotEmpty)
                  StatusPill(label: tc.publicCourseType, color: scheme.tertiary),
                if (watch.volunteerGrade != null)
                  StatusPill(
                      label: '第${watch.volunteerGrade}志愿',
                      color: scheme.primary,
                      icon: Icons.how_to_vote_outlined),
                if (tc.isConflict)
                  StatusPill(
                      label: watch.allowConflict ? '冲突，仍会提交' : '冲突，只监控',
                      color: watch.allowConflict ? Colors.orange : scheme.error,
                      icon: Icons.warning_amber),
              ],
            ),
            const SizedBox(height: 10),
            CapacityBar(
                selected: tc.numberOfSelected, capacity: tc.classCapacity),
            if (watch.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(watch.note, style: TextStyle(fontSize: 12, color: color)),
            ],
            if (watch.lastCheckedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                  '上次检查 ${formatClock(watch.lastCheckedAt!)}  已提交 ${watch.attempts} 次',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            if (watch.lastResultAt != null && watch.lastRawResult != null) ...[
              const SizedBox(height: 2),
              Text(
                  '服务器回复 ${formatClock(watch.lastResultAt!)}：${watch.lastRawResult}',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (watch.status == WatchStatus.needsSetup)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _completeSetup(context, ref, watch),
                      icon: const Icon(Icons.build_outlined, size: 18),
                      label: const Text('完成选择'),
                    ),
                  )
                else if (watch.status == WatchStatus.grabbed)
                  const Expanded(
                      child: Center(
                          child: Text('已抢到',
                              style: TextStyle(fontWeight: FontWeight.w700))))
                else ...[
                  if (watch.status == WatchStatus.paused)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => engine.resumeWatch(watch.id),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('继续'),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => engine.pauseWatch(watch.id),
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text('暂停'),
                      ),
                    ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => engine.removeWatch(watch.id),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '移除',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (Color, String, IconData) _statusVisual(
      WatchStatus status, ColorScheme scheme) {
    switch (status) {
      case WatchStatus.watching:
        return (scheme.primary, '监控中', Icons.radar);
      case WatchStatus.grabbing:
        return (Colors.orange, '提交中', Icons.bolt);
      case WatchStatus.grabbed:
        return (Colors.green, '已抢到', Icons.check_circle);
      case WatchStatus.paused:
        return (scheme.onSurfaceVariant, '已暂停', Icons.pause_circle);
      case WatchStatus.needsSetup:
        return (Colors.amber.shade800, '待完善', Icons.error_outline);
      case WatchStatus.failed:
        return (scheme.error, '已停止', Icons.cancel);
    }
  }

  Future<void> _completeSetup(
      BuildContext context, WidgetRef ref, Watch watch) async {
    final tc = watch.teachingClass;
    String? testId = watch.selectedTestTeachingClassId;
    String? bookSelection = watch.bookSelection;
    try {
      final course = ref.read(courseServiceProvider);
      if (tc.hasTest && (testId == null || testId.isEmpty)) {
        final rows = await course.fetchTestCourses(
          tc: tc,
          studentCode: watch.studentCode,
          batchCode: watch.batchCode,
          campus: watch.campus,
          kind: watch.kind,
        );
        if (!context.mounted) return;
        if (rows.isEmpty) {
          showToast(context, '没有可选的实验教学班', success: false);
          return;
        }
        testId = await showAdaptiveSheet<String>(
          context,
          builder: (context) => TestClassPicker(list: rows),
        );
        if (testId == null || testId.isEmpty || !context.mounted) return;
      }
      if (tc.hasBook &&
          watch.textbookOrderingOpen &&
          (bookSelection == null || bookSelection.isEmpty)) {
        final reasons =
            await ref.read(infoServiceProvider).fetchTextbookReasons();
        final options = [
          for (final o in await course.fetchTextbookOptions(
            studentCode: watch.studentCode,
            batchCode: watch.batchCode,
            teachingClassId: tc.teachingClassId,
          ))
            o.copyWith(reasonCodes: reasons),
        ];
        if (!context.mounted) return;
        if (options.isEmpty) {
          showToast(context, '没有教材清单，暂时无法完成', success: false);
          return;
        }
        final selection = await showAdaptiveSheet<TextbookSelection>(
          context,
          scrollControlled: true,
          builder: (context) => TextbookPicker(options: options),
        );
        if (selection == null || !context.mounted) return;
        bookSelection = selection.jcxx;
      }
      ref.read(monitorEngineProvider).configureWatch(
            watch.id,
            testTeachingClassId: testId,
            bookSelection: bookSelection,
          );
      if (!context.mounted) return;
      final complete = watch.status != WatchStatus.needsSetup;
      showToast(
        context,
        complete ? '已保存，继续监控' : watch.note,
        success: complete,
      );
    } catch (error) {
      if (context.mounted) {
        showToast(context, '加载失败：$error', success: false);
      }
    }
  }
}

/// The rolling activity log. As a [panel] it fills its column and always shows
/// (with an empty hint); otherwise it is a compact strip under the list that
/// hides while there is nothing to show.
class _ActivityLog extends ConsumerWidget {
  const _ActivityLog({required this.panel});
  final bool panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(monitorLogProvider);
    final id = ref.watch(activeAccountIdProvider);
    if (!panel && events.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: panel ? null : const BoxConstraints(maxHeight: 132),
      margin: panel
          ? const EdgeInsets.fromLTRB(4, 8, 16, 24)
          : const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('日志',
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (events.isNotEmpty && id != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: '清空',
                  onPressed: () =>
                      ref.read(monitorLogOfProvider(id).notifier).clear(),
                  icon: const Icon(Icons.clear_all),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Text('开始监控后，过程会记录在这里',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  )
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[i];
                      final c = e.success == null
                          ? scheme.onSurfaceVariant
                          : e.success!
                              ? Colors.green
                              : scheme.error;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${formatClock(e.at)}  ${e.message}',
                            style: TextStyle(fontSize: 12, color: c)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
