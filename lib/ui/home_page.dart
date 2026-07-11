/// Home: student identity, active batch selector, monitor status, quick actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';
import 'widgets.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final scheme = Theme.of(context).colorScheme;
    final running = ref.watch(monitorRunningProvider);
    final watchCount = ref.watch(watchCountProvider);
    final student = session.student;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: const Text('首页'),
          actions: [
            IconButton(
              tooltip: '刷新轮次',
              icon: const Icon(Icons.refresh),
              onPressed: () => _reloadContext(context, ref),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileCard(student: student, scheme: scheme),
                const SizedBox(height: 16),
                const _SectionLabel('选课轮次'),
                const SizedBox(height: 8),
                _BatchSelector(session: session),
                const SizedBox(height: 16),
                const _SectionLabel('抢课监控'),
                const SizedBox(height: 8),
                _MonitorSummary(running: running, watchCount: watchCount),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _reloadContext(BuildContext context, WidgetRef ref) async {
    final mgr = ref.read(sessionManagerProvider);
    final code = mgr.studentCode;
    if (code == null) return;
    try {
      final (info, batches) = await mgr.auth.loadContext(code);
      mgr.student = info;
      mgr.batches = batches;
      if (context.mounted) showToast(context, '轮次已刷新', success: true);
      // Nudge the session state so UI rebuilds.
      ref.read(sessionProvider.notifier).setActiveBatch(mgr.activeBatch ?? (batches.isNotEmpty ? batches.first : ElectiveBatch(code: '', name: '', batchType: '', canSelect: false)));
    } catch (e) {
      if (context.mounted) showToast(context, '刷新失败：$e', success: false);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.student, required this.scheme});
  final StudentInfo? student;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.15),
            child: Icon(Icons.school, color: scheme.onPrimaryContainer, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student?.name.isNotEmpty == true ? student!.name : '同学',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  student?.studentCode ?? '',
                  style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
                ),
                if (student?.majorName.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    [student?.collegeName, student?.majorName].where((e) => (e ?? '').isNotEmpty).join(' · '),
                    style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchSelector extends ConsumerWidget {
  const _BatchSelector({required this.session});
  final SessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (session.batches.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Expanded(child: Text('当前没有可见的选课轮次。开放后点击右上角刷新。')),
            ],
          ),
        ),
      );
    }
    return Card(
      child: RadioGroup<String>(
        groupValue: session.activeBatch?.code,
        onChanged: (code) {
          if (code == null) return;
          final batch = session.batches.firstWhere((b) => b.code == code);
          ref.read(sessionProvider.notifier).setActiveBatch(batch);
        },
        child: Column(
          children: [
            for (final batch in session.batches)
              RadioListTile<String>(
                value: batch.code,
                title: Text(batch.name.isEmpty ? batch.code : batch.name),
                subtitle: batch.beginTime.isNotEmpty
                    ? Text('${batch.beginTime}  →  ${batch.endTime}', style: const TextStyle(fontSize: 12))
                    : null,
                secondary: StatusPill(
                  label: batch.canSelect ? '开放' : '未开放',
                  color: batch.canSelect ? Colors.green : scheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonitorSummary extends ConsumerWidget {
  const _MonitorSummary({required this.running, required this.watchCount});
  final bool running;
  final int watchCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final watches = ref.watch(watchesProvider);
    final grabbed = watches.where((w) => w.status == WatchStatus.grabbed).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: running ? Colors.green.withValues(alpha: 0.15) : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    running ? Icons.radar : Icons.pause_circle_outline,
                    color: running ? Colors.green : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(running ? '监控运行中' : '监控已停止',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('$watchCount 个课程监控中 · 已抢到 $grabbed',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                Switch(
                  value: running,
                  onChanged: (v) {
                    final engine = ref.read(monitorEngineProvider);
                    v ? engine.start() : engine.stop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
