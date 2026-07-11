/// Monitor page: the auto-grab watch list with live status, per-watch controls,
/// a master start/stop, and a rolling activity log.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import '../app/providers.dart';
import '../data/monitor_engine.dart';
import 'widgets.dart';

class MonitorPage extends ConsumerWidget {
  const MonitorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watches = ref.watch(watchesProvider);
    final running = ref.watch(monitorRunningProvider);
    final engine = ref.read(monitorEngineProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('监控', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (watches.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: running ? engine.stop : engine.start,
                  icon: Icon(running ? Icons.stop : Icons.play_arrow),
                  label: Text(running ? '停止全部' : '启动全部'),
                ),
            ],
          ),
        ),
        const _RunningBanner(),
        Expanded(
          child: watches.isEmpty
              ? const EmptyState(
                  icon: Icons.radar,
                  title: '还没有监控课程',
                  subtitle: '在「选课」页找到心仪的教学班，点击「监控抢课」加入。有人退课时会自动抢占。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: watches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _WatchCard(watch: watches[i]),
                ),
        ),
        const _ActivityLog(),
      ],
    );
  }
}

class _RunningBanner extends ConsumerWidget {
  const _RunningBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(monitorRunningProvider);
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
            child: Text('正在监控课程容量变动，发现空位将立即抢占',
                style: TextStyle(color: scheme.onSurface, fontSize: 13)),
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

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(watch.teachingClass.courseName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                StatusPill(label: label, color: color, icon: icon),
              ],
            ),
            const SizedBox(height: 2),
            Text(tc.displayTitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            if (tc.teachingPlace.isNotEmpty)
              Text(tc.teachingPlace, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 10),
            CapacityBar(selected: tc.numberOfSelected, capacity: tc.classCapacity),
            if (watch.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(watch.note, style: TextStyle(fontSize: 12, color: color)),
            ],
            if (watch.lastCheckedAt != null) ...[
              const SizedBox(height: 4),
              Text('上次检查：${_fmtTime(watch.lastCheckedAt!)} · 已尝试 ${watch.attempts} 次',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (watch.status == WatchStatus.needsSetup)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _showSetupHelp(context, watch),
                      icon: const Icon(Icons.build_outlined, size: 18),
                      label: const Text('去完成选择'),
                    ),
                  )
                else if (watch.status == WatchStatus.grabbed)
                  const Expanded(child: Center(child: Text('🎉 已抢到', style: TextStyle(fontWeight: FontWeight.w700))))
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

  (Color, String, IconData) _statusVisual(WatchStatus status, ColorScheme scheme) {
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

  void _showSetupHelp(BuildContext context, Watch watch) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要完成选择'),
        content: Text(watch.note.isEmpty
            ? '该教学班包含实验课或需要教材征订，请回到「选课」页重新加入监控并完成选择。'
            : watch.note),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
      ),
    );
  }

  static String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class _ActivityLog extends ConsumerStatefulWidget {
  const _ActivityLog();
  @override
  ConsumerState<_ActivityLog> createState() => _ActivityLogState();
}

class _ActivityLogState extends ConsumerState<_ActivityLog> {
  final List<MonitorEvent> _events = [];

  @override
  Widget build(BuildContext context) {
    ref.listen(monitorEventsProvider, (_, next) {
      next.whenData((e) {
        if (e.message.isEmpty) return;
        setState(() {
          _events.insert(0, e);
          if (_events.length > 50) _events.removeLast();
        });
      });
    });

    if (_events.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 132),
      margin: const EdgeInsets.all(12),
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
              Icon(Icons.receipt_long, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('活动日志', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, i) {
                final e = _events[i];
                final c = e.success == null
                    ? scheme.onSurfaceVariant
                    : e.success!
                        ? Colors.green
                        : scheme.error;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${_WatchCard._fmtTime(e.at)}  ${e.message}',
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
