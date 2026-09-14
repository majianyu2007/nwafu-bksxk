/// Home: student identity, active batch selector, monitor status, quick actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import '../app/providers.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';
import 'batch_pick_dialog.dart';
import 'layout.dart';
import 'widgets.dart';

final noticesProvider = FutureProvider.autoDispose<List<Notice>>(
    (ref) => ref.read(infoServiceProvider).fetchNotices());

final creditInfoProvider = FutureProvider.autoDispose<CreditInfo>((ref) async {
  ref.watch(selectionDataRevisionProvider);
  final s = ref.watch(sessionProvider);
  final b = s.activeBatch;
  final st = s.student;
  if (st == null || b == null) return CreditInfo.empty;
  return ref.read(infoServiceProvider).fetchCreditInfo(
        studentCode: st.studentCode,
        electiveBatchCode: b.code,
        batchType: b.batchType,
      );
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final scheme = Theme.of(context).colorScheme;
    final running = ref.watch(monitorRunningProvider);
    final watchCount = ref.watch(watchCountProvider);
    final student = session.student;

    final refresh = IconButton(
      tooltip: '刷新轮次',
      icon: const Icon(Icons.refresh),
      onPressed: () => _reloadContext(context, ref),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = WindowClass.of(constraints.maxWidth).isWide;
        final gutter = pageGutter(constraints.maxWidth);

        // Rounds are the thing to act on; the other cards are status. On wide
        // windows they sit side by side instead of one long stretched column.
        final batches = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionLabel('选课轮次'),
            const SizedBox(height: 8),
            _BatchClosedBanner(session: session),
            _BatchSelector(session: session),
          ],
        );
        final status = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionLabel('选课学分'),
            const SizedBox(height: 8),
            const _CreditCard(),
            const SizedBox(height: 16),
            const _NoticesCard(),
            const SizedBox(height: 16),
            const _SectionLabel('抢课监控'),
            const SizedBox(height: 8),
            _MonitorSummary(running: running, watchCount: watchCount),
          ],
        );

        return CustomScrollView(
          slivers: [
            if (wide)
              SliverToBoxAdapter(
                child: PageHeader(
                  title: '首页',
                  padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 8),
                  actions: [refresh],
                ),
              )
            else
              SliverAppBar.large(title: const Text('首页'), actions: [refresh]),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileCard(student: student, scheme: scheme),
                    const SizedBox(height: 16),
                    if (wide)
                      TwoColumn(
                        primary: batches,
                        secondary: status,
                        primaryFlex: 3,
                        secondaryFlex: 2,
                        gap: 20,
                      )
                    else ...[
                      batches,
                      const SizedBox(height: 16),
                      const _NoticesCard(),
                      const SizedBox(height: 16),
                      const _SectionLabel('选课学分'),
                      const SizedBox(height: 8),
                      const _CreditCard(),
                      const SizedBox(height: 16),
                      const _SectionLabel('抢课监控'),
                      const SizedBox(height: 8),
                      _MonitorSummary(running: running, watchCount: watchCount),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _reloadContext(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(sessionProvider.notifier);
    try {
      await controller.reloadContext();
      ref.invalidate(noticesProvider);
      if (context.mounted) showToast(context, '选课信息已刷新', success: true);
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
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
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
            child:
                Icon(Icons.school, color: scheme.onPrimaryContainer, size: 30),
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
                  style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
                ),
                if (student?.majorName.isNotEmpty == true ||
                    student?.schoolClassName.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      student?.collegeName,
                      student?.majorName,
                      if (student?.grade.isNotEmpty == true)
                        '${student!.grade}级',
                      student?.schoolClassName,
                    ].where((e) => (e ?? '').isNotEmpty).join(' · '),
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
                subtitle: Text(
                  [
                    if (batch.beginTime.isNotEmpty)
                      '${batch.beginTime}  →  ${batch.endTime}',
                    if (!batch.canSelect && batch.noSelectReason.isNotEmpty)
                      batch.noSelectReason,
                  ].join('\n'),
                  style: const TextStyle(fontSize: 12),
                ),
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
    final grabbed =
        watches.where((w) => w.status == WatchStatus.grabbed).length;

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
                    color: running
                        ? Colors.green.withValues(alpha: 0.15)
                        : scheme.surfaceContainerHighest,
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
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('$watchCount 个课程监控中 · 已抢到 $grabbed',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 13)),
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

class _NoticesCard extends ConsumerWidget {
  const _NoticesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noticesAsync = ref.watch(noticesProvider);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '选课公告',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => ref.invalidate(noticesProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '刷新公告',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            noticesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Row(
                children: [
                  Icon(Icons.cloud_off_outlined, color: scheme.error),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('公告加载失败')),
                  TextButton(
                    onPressed: () => ref.invalidate(noticesProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
              data: (notices) {
                if (notices.isEmpty) {
                  return Text(
                    '当前没有新公告',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  );
                }
                return SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: notices.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final notice = notices[i];
                      return ActionChip(
                        onPressed: () =>
                            _showNoticeDetail(context, ref, notice.wid),
                        label: Text(
                          notice.title.length > 14
                              ? '${notice.title.substring(0, 14)}…'
                              : notice.title,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showNoticeDetail(BuildContext context, WidgetRef ref, String wid) {
    showAdaptiveSheet<void>(
      context,
      builder: (_) => _NoticeDetailSheet(wid: wid, ref: ref),
    );
  }
}

class _NoticeDetailSheet extends StatelessWidget {
  const _NoticeDetailSheet({required this.wid, required this.ref});
  final String wid;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Notice?>(
      future: ref.read(infoServiceProvider).fetchNoticeDetail(wid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return SizedBox(
            height: 200,
            child: Center(
              child: Text(
                '公告加载失败：${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final notice = snapshot.data;
        if (notice == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('暂无内容')),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(notice.title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              if (notice.timeDescription.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(notice.timeDescription,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(notice.content),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _CreditCard extends ConsumerWidget {
  const _CreditCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditAsync = ref.watch(creditInfoProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('选课学分',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                IconButton(
                  onPressed: () => ref.invalidate(creditInfoProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '刷新学分',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            creditAsync.when(
              data: (info) {
                // Same three figures, same labels, as the official 学分 chart.
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            label: '总学分',
                            value: info.totalCredit.toStringAsFixed(1),
                          ),
                        ),
                        Expanded(
                          child: _StatTile(
                            label: '已获学分',
                            value: info.getCredit.toStringAsFixed(1),
                          ),
                        ),
                        Expanded(
                          child: _StatTile(
                            label: '本轮已选',
                            value: info.selectedCredit.toStringAsFixed(1),
                          ),
                        ),
                      ],
                    ),
                    if (info.noSelectReason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              info.noSelectReason,
                              style:
                                  TextStyle(fontSize: 12, color: scheme.error),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(label: '无法选课', color: scheme.error),
                        ],
                      ),
                    ],
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 40,
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              ),
              error: (error, _) => Row(
                children: [
                  Icon(Icons.cloud_off_outlined, color: scheme.error, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('学分加载失败')),
                  TextButton(
                    onPressed: () => ref.invalidate(creditInfoProvider),
                    child: const Text('重试'),
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

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: scheme.primary)),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Shows a warning when the active batch is not open, with a re-pick action
/// that reopens the batch-pick dialog.
class _BatchClosedBanner extends ConsumerWidget {
  const _BatchClosedBanner({required this.session});
  final SessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = session.activeBatch;
    final batches = session.batches;
    if (batches.isEmpty) return const SizedBox.shrink();
    if (batch != null && batch.canSelect) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              batch == null
                  ? '尚未选择选课轮次，请先选择一个轮次。'
                  : '当前轮次「${batch.name.isEmpty ? batch.code : batch.name}」未开放选课。',
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () =>
                showBatchPickDialog(context, ref, batches: batches),
            child: Text(
              batch == null ? '去选择' : '重新选择',
              style: TextStyle(
                  color: scheme.onErrorContainer, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
