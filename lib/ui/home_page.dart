/// Home: who is signed in, the round to act on, credits, notices, contact,
/// and the monitor at a glance.
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

/// The home-page aggregate: notices, common problems, contact, stop notice.
final publicInfoProvider = FutureProvider.autoDispose<PublicInfo>(
    (ref) => ref.watch(publicInfoServiceProvider).fetchPublicInfo());

/// The shown account's credit summary for its active round.
final creditInfoProvider = FutureProvider.autoDispose<CreditInfo>((ref) async {
  ref.watch(currentSelectionRevisionProvider);
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
    final student = session.student;

    final refresh = IconButton(
      tooltip: '刷新',
      icon: const Icon(Icons.refresh),
      onPressed: () => _reload(context, ref),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = WindowClass.of(constraints.maxWidth).isWide;
        final gutter = pageGutter(constraints.maxWidth);

        final rounds = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionLabel('选课轮次'),
            const SizedBox(height: 8),
            _BatchClosedBanner(session: session),
            _BatchSelector(session: session),
            const SizedBox(height: 16),
            const _SectionLabel('学分'),
            const SizedBox(height: 8),
            const _CreditCard(),
          ],
        );
        const side = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel('监控'),
            SizedBox(height: 8),
            _MonitorSummary(),
            SizedBox(height: 16),
            _SectionLabel('公告'),
            SizedBox(height: 8),
            _NoticesCard(),
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
                    _ProfileCard(student: student),
                    const SizedBox(height: 16),
                    const _StopInfoBanner(),
                    if (wide)
                      TwoColumn(
                        primary: rounds,
                        secondary: side,
                        primaryFlex: 3,
                        secondaryFlex: 2,
                        gap: 20,
                      )
                    else ...[
                      rounds,
                      const SizedBox(height: 16),
                      side,
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

  Future<void> _reload(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(currentSessionControllerProvider).reloadContext();
      ref.invalidate(publicInfoProvider);
      if (context.mounted) showToast(context, '已刷新', success: true);
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
  const _ProfileCard({required this.student});
  final StudentInfo? student;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = student;
    final detail = [
      s?.collegeName,
      s?.majorName,
      if (s?.grade.isNotEmpty == true) '${s!.grade}级',
      s?.schoolClassName,
    ].where((e) => (e ?? '').isNotEmpty).join('  ');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.12),
            child: Icon(Icons.school, color: scheme.onPrimaryContainer, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s?.name.isNotEmpty == true ? s!.name : '同学',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  [s?.studentCode ?? '', if (s?.campusName.isNotEmpty == true) s!.campusName]
                      .where((e) => e.isNotEmpty)
                      .join('  '),
                  style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.85)),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                        fontSize: 12,
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The school's 停止说明 text, shown when selection is halted.
class _StopInfoBanner extends ConsumerWidget {
  const _StopInfoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(publicInfoProvider).asData?.value;
    if (info == null || info.stopInfo.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: NoticeStrip(icon: Icons.campaign_outlined, error: true, text: info.stopInfo, margin: EdgeInsets.zero),
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
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('现在没有可见的选课轮次，开放后点右上角刷新。'),
        ),
      );
    }
    return Card(
      child: RadioGroup<String>(
        groupValue: session.activeBatch?.code,
        onChanged: (code) {
          if (code == null) return;
          final batch = session.batches.firstWhere((b) => b.code == code);
          ref.read(currentSessionControllerProvider).setActiveBatch(batch);
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
                      '${batch.beginTime} 至 ${batch.endTime}',
                    [
                      if (batch.typeName.isNotEmpty) batch.typeName,
                      if (batch.tacticName.isNotEmpty) batch.tacticName,
                      if (batch.schoolTermName.isNotEmpty) batch.schoolTermName,
                    ].join('  '),
                    if (!batch.canSelect && batch.noSelectReason.isNotEmpty)
                      batch.noSelectReason,
                  ].where((e) => e.isNotEmpty).join('\n'),
                  style: const TextStyle(fontSize: 12),
                ),
                isThreeLine: true,
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
  const _MonitorSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final running = ref.watch(monitorRunningProvider);
    final watches = ref.watch(watchesProvider);
    final active = ref.watch(watchCountProvider);
    final grabbed =
        watches.where((w) => w.status == WatchStatus.grabbed).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
                  Text(running ? '监控运行中' : '监控未运行',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('$active 个监控中，已抢到 $grabbed',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
            Switch(
              value: running,
              onChanged: watches.isEmpty
                  ? null
                  : (v) {
                      final engine = ref.read(monitorEngineProvider);
                      v ? engine.start() : engine.stop();
                    },
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
    final infoAsync = ref.watch(publicInfoProvider);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: infoAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Row(
            children: [
              Icon(Icons.cloud_off_outlined, color: scheme.error),
              const SizedBox(width: 8),
              const Expanded(child: Text('公告加载失败')),
              TextButton(
                onPressed: () => ref.invalidate(publicInfoProvider),
                child: const Text('重试'),
              ),
            ],
          ),
          data: (info) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (info.notices.isEmpty)
                Text('暂无公告',
                    style: TextStyle(color: scheme.onSurfaceVariant))
              else
                for (final n in info.notices.take(7))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: n.timeDescription.isEmpty ? null : Text(n.timeDescription),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => _showNoticeDetail(context, ref, n),
                  ),
              if (info.problems.isNotEmpty) ...[
                const Divider(height: 20),
                Text('常见问题',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: scheme.onSurfaceVariant)),
                for (final p in info.problems)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => _showProblem(context, p),
                  ),
              ],
              if (!info.consult.isEmpty) ...[
                const Divider(height: 20),
                Text(
                  [
                    if (info.consult.unitName.isNotEmpty) info.consult.unitName,
                    if (info.consult.phoneNumber.isNotEmpty) info.consult.phoneNumber,
                    if (info.consult.callPhoneNumber.isNotEmpty) info.consult.callPhoneNumber,
                    if (info.consult.email.isNotEmpty) info.consult.email,
                    if (info.consult.qqNumber.isNotEmpty) 'QQ ${info.consult.qqNumber}',
                  ].join('  '),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showNoticeDetail(BuildContext context, WidgetRef ref, Notice notice) {
    final info = ref.read(publicInfoServiceProvider);
    showAdaptiveSheet<void>(
      context,
      builder: (_) => FutureBuilder<Notice?>(
        future: info.fetchNoticeDetail(notice.wid),
        builder: (context, snapshot) {
          final n = snapshot.data ?? notice;
          return _TextSheet(
            title: n.title,
            caption: n.timeDescription,
            body: snapshot.connectionState == ConnectionState.waiting
                ? null
                : (n.content.isEmpty ? '暂无内容' : n.content),
          );
        },
      ),
    );
  }

  void _showProblem(BuildContext context, ProblemEntry p) {
    showAdaptiveSheet<void>(
      context,
      builder: (_) => _TextSheet(
          title: p.title, caption: p.timeDescription, body: p.content),
    );
  }
}

class _TextSheet extends StatelessWidget {
  const _TextSheet({required this.title, required this.caption, this.body});
  final String title;
  final String caption;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(caption,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          if (body == null)
            const Center(child: CircularProgressIndicator())
          else
            Flexible(child: SingleChildScrollView(child: SelectableText(body!))),
        ],
      ),
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
        child: creditAsync.when(
          data: (info) => Column(
            children: [
              Row(
                children: [
                  Expanded(child: _StatTile(label: '总学分', value: _fmt(info.totalCredit))),
                  Expanded(child: _StatTile(label: '已获学分', value: _fmt(info.getCredit))),
                  Expanded(child: _StatTile(label: '已选学分', value: _fmt(info.selectedCredit))),
                ],
              ),
              if (info.requirements.isNotEmpty) ...[
                const Divider(height: 20),
                for (final r in info.requirements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(r.category,
                              style: TextStyle(
                                  fontSize: 13, color: scheme.onSurfaceVariant)),
                        ),
                        Text('已修 ${r.earned}  要求 ${r.required}',
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
              ],
              if (info.noSelectReason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(info.noSelectReason,
                    style: TextStyle(fontSize: 12, color: scheme.error)),
              ],
            ],
          ),
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
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
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

/// Shows a warning when the active batch is not open, with a re-pick action.
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NoticeStrip(
        icon: Icons.warning_amber,
        error: true,
        margin: EdgeInsets.zero,
        text: batch == null
            ? '还没有选择轮次'
            : '「${batch.name.isEmpty ? batch.code : batch.name}」未开放',
        action: TextButton(
          onPressed: () => showBatchPickDialog(context, ref, batches: batches),
          child: Text(batch == null ? '选择' : '重选',
              style: TextStyle(
                  color: scheme.onErrorContainer, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
