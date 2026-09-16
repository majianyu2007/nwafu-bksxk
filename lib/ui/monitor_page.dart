/// Monitor page: the auto-grab watch list with live status, per-watch controls,
/// a master start/stop, and a rolling activity log.
///
/// On wide windows the watch cards form a grid and the activity log becomes a
/// full-height side panel instead of a cramped strip under the list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import '../app/providers.dart';
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideLog = constraints.maxWidth >= _kSideLogBreakpoint;
        final list = _WatchList(watches: watches);

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
                    label: Text(running ? '停止监控' : '启动监控'),
                  ),
              ],
            ),
            const _RunningBanner(),
            const _HaltReasonBanner(),
            const _PlanBanner(),
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
  const _WatchList({required this.watches});
  final List<Watch> watches;

  @override
  Widget build(BuildContext context) {
    if (watches.isEmpty) {
      return const EmptyState(
        icon: Icons.radar,
        title: '还没有监控课程',
        subtitle: '在「选课」页找到心仪的教学班，点击「监控抢课」加入。有人退课时会自动抢占。',
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
          children: [for (final w in watches) _WatchCard(watch: w)],
        ),
      ],
    );
  }
}

class _RunningBanner extends ConsumerWidget {
  const _RunningBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(monitorRunningProvider);
    final plan = ref.watch(planControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    if (!running) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const _PulsingDot(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              plan.armed && !plan.batchOpen
                  ? '正在监控容量，等待轮次开放后自动提交'
                  : '正在监控课程容量，发现空位将立即提交',
              style: TextStyle(color: scheme.onSurface, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends ConsumerWidget {
  const _ModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planControllerProvider);
    final controller = ref.read(planControllerProvider.notifier);
    return PopupMenuButton<String>(
      tooltip: '选择监控模式',
      onSelected: (value) {
        if (value == 'wait') {
          controller.arm();
        } else {
          controller.disarm();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'now',
          child: ListTile(
            leading: Icon(Icons.bolt_outlined),
            title: Text('立即抢课'),
            subtitle: Text('发现空位立即提交'),
          ),
        ),
        PopupMenuItem(
          value: 'wait',
          child: ListTile(
            leading: Icon(Icons.schedule),
            title: Text('等待轮次开放'),
            subtitle: Text('开放后再自动提交'),
          ),
        ),
      ],
      child: Chip(
        avatar:
            Icon(plan.armed ? Icons.schedule : Icons.bolt_outlined, size: 18),
        label: Text(plan.armed ? '等待开放' : '立即抢课'),
      ),
    );
  }
}

class _PlanBanner extends ConsumerWidget {
  const _PlanBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    if (!plan.armed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(plan.checking ? Icons.sync : Icons.schedule,
              color: scheme.onTertiaryContainer, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('计划模式已就绪',
                    style: TextStyle(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700)),
                Text(
                  plan.batchOpen
                      ? '选课已开放，正在提交计划'
                      : '正在等待选课开放，一旦开放立即提交${plan.lastCheckedAt != null ? '（上次检查 ${_fmtHms(plan.lastCheckedAt!)}）' : ''}',
                  style: TextStyle(
                      color: scheme.onTertiaryContainer, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtHms(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class _HaltReasonBanner extends ConsumerWidget {
  const _HaltReasonBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(monitorChangesProvider);
    final engine = ref.read(monitorEngineProvider);
    final reason = engine.stopReason;
    final scheme = Theme.of(context).colorScheme;
    if (reason == null || engine.isRunning) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.pause_circle, color: scheme.onErrorContainer, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('监控已自动停止：$reason。请稍后手动重新启动。',
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_c),
      child: const Icon(Icons.circle, size: 12, color: Colors.green),
    );
  }
}

class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.watch});
  final Watch watch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final engine = ref.read(monitorEngineProvider);
    final tc = watch.teachingClass;
    final (color, label, icon) = _statusVisual(watch.status, scheme);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(watch.teachingClass.courseName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                StatusPill(label: label, color: color, icon: icon),
              ],
            ),
            const SizedBox(height: 2),
            Text(tc.displayTitle,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            if (tc.teachingPlace.isNotEmpty)
              Text(tc.teachingPlace,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            if (watch.volunteerGrade != null || tc.isConflict) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (watch.volunteerGrade != null)
                    StatusPill(
                        label: '第${watch.volunteerGrade}志愿',
                        color: scheme.primary,
                        icon: Icons.how_to_vote_outlined),
                  if (tc.isConflict)
                    StatusPill(
                        label: watch.allowConflict ? '冲突·仍会提交' : '冲突·只监控不提交',
                        color:
                            watch.allowConflict ? Colors.orange : scheme.error,
                        icon: Icons.warning_amber),
                ],
              ),
            ],
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
                  '上次检查：${_fmtTime(watch.lastCheckedAt!)} · 已尝试 ${watch.attempts} 次',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            if (watch.lastResultAt != null && watch.lastRawResult != null) ...[
              const SizedBox(height: 2),
              Text(
                  '服务器回执：${watch.lastRawResult} (${_fmtTime(watch.lastResultAt!)})',
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
                      label: const Text('去完成选择'),
                    ),
                  )
                else if (watch.status == WatchStatus.grabbed)
                  const Expanded(
                      child: Center(
                          child: Text('🎉 已抢到',
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
        return (Colors.orange, '抢课中', Icons.bolt);
      case WatchStatus.grabbed:
        return (Colors.green, '已抢到', Icons.check_circle);
      case WatchStatus.paused:
        return (scheme.onSurfaceVariant, '已暂停', Icons.pause_circle);
      case WatchStatus.needsSetup:
        return (Colors.amber.shade800, '待完善', Icons.error_outline);
      case WatchStatus.failed:
        return (scheme.error, '失败', Icons.cancel);
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
          showToast(context, '未获取到可选实验教学班', success: false);
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
          showToast(context, '未获取到教材清单，暂时无法完成设置', success: false);
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
        complete ? '选择已保存，课程已恢复监控' : watch.note,
        success: complete,
      );
    } catch (error) {
      if (context.mounted) {
        showToast(context, '加载选项失败：$error', success: false);
      }
    }
  }

  static String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
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
              Text('活动日志',
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              if (events.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: '清空日志',
                  onPressed: () =>
                      ref.read(monitorLogProvider.notifier).clear(),
                  icon: const Icon(Icons.clear_all),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Text('监控启动后，抢课过程会记录在这里',
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
                        child: Text(
                            '${_WatchCard._fmtTime(e.at)}  ${e.message}',
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
