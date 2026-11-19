/// 学业进度: credits earned against the training plan, as a tree of course
/// groups. Opens from the cached copy; refresh pulls from 学业完成查询.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/degree_providers.dart';
import '../app/edu_providers.dart';
import '../core/errors.dart';
import '../data/degree_audit.dart';
import 'edu_login_page.dart';
import 'layout.dart';
import 'widgets.dart';
import 'widgets/glass.dart';

class DegreePage extends ConsumerStatefulWidget {
  const DegreePage({super.key});

  @override
  ConsumerState<DegreePage> createState() => _DegreePageState();
}

class _DegreePageState extends ConsumerState<DegreePage> {
  bool _onlyShort = false;
  bool _includeSelected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(degreeProvider);
      if (ref.read(eduSessionProvider).signedIn && !s.loading) {
        // Refresh on open; the cached copy stays on screen meanwhile.
        ref.read(degreeProvider.notifier).sync();
      }
    });
  }

  Future<void> _login() async {
    final ok = await pushEduLogin(context);
    if (ok == true && mounted && !ref.read(degreeProvider).loading) {
      await ref.read(degreeProvider.notifier).sync();
    }
  }

  Future<void> _sync() async {
    if (!ref.read(eduSessionProvider).signedIn) {
      await _login();
      return;
    }
    await ref.read(degreeProvider.notifier).sync();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      eduSessionProvider.select((s) => s.signedIn ? s.account?.username : null),
      (prev, next) {
        if (next != null && next != prev) {
          ref.read(degreeProvider.notifier).sync();
        }
      },
    );
    final signedIn = ref.watch(eduSessionProvider.select((s) => s.signedIn));
    final state = ref.watch(degreeProvider);
    final audit = signedIn ? state.audit : null;
    final theme = Theme.of(context);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('学业进度'),
        actions: [
          if (audit != null)
            IconButton(
              tooltip: _includeSelected ? '切换回当前已修' : '按本学期全过预计进度',
              isSelected: _includeSelected,
              onPressed: () =>
                  setState(() => _includeSelected = !_includeSelected),
              icon: const Icon(Icons.auto_graph_outlined),
              selectedIcon: const Icon(Icons.auto_graph),
            ),
          if (audit != null)
            IconButton(
              tooltip: _onlyShort ? '显示全部课组' : '只看没修够的',
              isSelected: _onlyShort,
              onPressed: () => setState(() => _onlyShort = !_onlyShort),
              icon: const Icon(Icons.filter_alt_outlined),
              selectedIcon: const Icon(Icons.filter_alt),
            ),
          if (signedIn)
            IconButton(
              tooltip: '刷新',
              onPressed: state.loading ? null : _sync,
              icon: const Icon(Icons.sync),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!signedIn)
                      _Message(
                        icon: Icons.school_outlined,
                        title: '登录统一身份认证',
                        text: '登录后可以查看培养方案里每类课修了多少学分。',
                        action: FilledButton(
                          onPressed: _login,
                          child: const Text('去登录'),
                        ),
                      )
                    else ...[
                      if (state.loading) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ],
                      if (state.error != null) ...[
                        _ErrorCard(
                          error: state.error!,
                          hasCache: audit != null,
                          retry: state.loading ? null : _sync,
                          login: _login,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (audit == null && !state.loading && state.error == null)
                        _Message(
                          icon: Icons.insights_outlined,
                          title: '还没有学业进度',
                          text: '刷新一次后，没网也能看。',
                          action: FilledButton(
                            onPressed: _sync,
                            child: const Text('刷新'),
                          ),
                        ),
                      if (audit != null && audit.plans.isEmpty)
                        const _Message(
                          icon: Icons.insights_outlined,
                          title: '没有查到培养方案',
                          text: '教务系统里还没有你的培养方案。',
                        ),
                      if (audit != null)
                        for (final plan in audit.plans) ...[
                          _PlanHeader(
                            plan: plan,
                            includeSelected: _includeSelected,
                          ),
                          const SizedBox(height: 12),
                          ..._buildPlanGroups(theme, plan),
                          const SizedBox(height: 20),
                        ],
                      if (audit != null)
                        Text(
                          '数据来自教务系统「学业完成查询」，以学校最后一次计算为准；'
                          '本学期刚选的课不算已修。',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
  List<Widget> _buildPlanGroups(ThemeData theme, DegreePlan plan) {
    final visible = [
      for (final g in plan.groups)
        if (!_onlyShort ||
            (_includeSelected
                ? (g.missing - (g.selected ?? 0)) > 0.001
                : g.short))
          g,
    ];
    if (visible.isEmpty && _onlyShort) {
      return [
        GlassCard(
          padding: const EdgeInsets.all(16),
          tint: Colors.green,
          tintAmount: 0.05,
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _includeSelected ? '按本学期全过预计，所有课组均已修够。' : '当前所有课组均已修够。',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final g in visible)
        _GroupCard(
          key: ValueKey(g.id),
          group: g,
          depth: 0,
          onlyShort: _onlyShort,
          includeSelected: _includeSelected,
        ),
    ];
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.plan, this.includeSelected = false});
  final DegreePlan plan;
  final bool includeSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = plan.selected ?? 0;
    final goal = plan.goal;
    final shownEarned = includeSelected ? plan.earned + selected : plan.earned;
    final shownMissing = includeSelected
        ? (plan.missing - selected).clamp(0.0, double.infinity).toDouble()
        : plan.missing;
    final shownProgress = goal <= 0
        ? plan.progress
        : (shownEarned / goal).clamp(0.0, 1.0);
    final shortLeaves = [
      for (final g in plan.shortLeaves)
        if (!includeSelected || (g.missing - (g.selected ?? 0)) > 0.001) g,
    ];
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name, style: theme.textTheme.titleMedium),
              ),
              if (includeSelected)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: StatusPill(
                    label: '含本学期预计',
                    color: scheme.tertiary,
                  ),
                ),
              if (plan.kind.isNotEmpty)
                Chip(
                  label: Text(plan.kind),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatCredit(shownEarned),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                TextSpan(
                  text: ' / ${formatCredit(goal)} 学分',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CreditBar(
            earned: shownEarned,
            selected: includeSelected ? 0 : selected,
            goal: goal,
            height: 12,
            passed: shownMissing <= 0 && goal > 0,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                shownMissing > 0
                    ? '${includeSelected ? '预计仍差' : '还差'} ${formatCredit(shownMissing)} 学分'
                    : (includeSelected ? '本学期全过即修够总学分' : '总学分已修够'),
              ),
              if (plan.selected != null)
                Text('本学期已选 ${formatCredit(selected)} 学分'),
              Text('${(shownProgress * 100).toStringAsFixed(0)}%'),
            ],
          ),
          if (plan.computedAt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '学校计算于 ${plan.computedAt}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (shortLeaves.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              includeSelected ? '本学期后预计仍差' : '还没修够',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in shortLeaves)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.secondaryContainer,
                    side: BorderSide.none,
                    label: Text(
                      '${g.name} 差 ${formatCredit(includeSelected ? (g.missing - (g.selected ?? 0)).clamp(0.0, double.infinity).toDouble() : g.missing)}',
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Earned credits solid, this term's selection lighter on top of it.
class _CreditBar extends StatelessWidget {
  const _CreditBar({
    required this.earned,
    required this.selected,
    required this.goal,
    this.height = 8,
    this.passed = false,
  });
  final double earned;
  final double selected;
  final double goal;
  final double height;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = goal <= 0 ? 1.0 : goal;
    final a = (earned / total).clamp(0.0, 1.0);
    final b = ((earned + selected) / total).clamp(0.0, 1.0);
    final color = passed || (goal > 0 && earned >= goal)
        ? Colors.green
        : scheme.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scheme.surfaceContainerHighest),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: b,
              child: ColoredBox(color: color.withValues(alpha: 0.3)),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: a,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatefulWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.depth,
    required this.onlyShort,
    this.includeSelected = false,
  });
  final DegreeGroup group;
  final int depth;
  final bool onlyShort;
  final bool includeSelected;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late bool _open = widget.depth == 0 && widget.group.short;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final inc = widget.includeSelected;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sel = g.selected ?? 0;
    final shownEarned = inc ? g.earned + sel : g.earned;
    final shownMissing = inc
        ? (g.missing - sel).clamp(0.0, double.infinity).toDouble()
        : g.missing;
    final isShort = inc ? shownMissing > 0.001 : g.short;
    final isDone = !isShort && (g.goal > 0 || g.passed);
    final children = [
      for (final c in g.children)
        if (!widget.onlyShort ||
            (inc ? (c.missing - (c.selected ?? 0)) > 0.001 : c.short))
          c,
    ];
    final details = [
      if (g.nature.isNotEmpty) g.nature,
      if (sel > 0) '本学期已选 ${formatCredit(sel)}',
      if (g.openCourses != null && g.openCourses! > 0)
        '本学期可选 ${g.openCourses} 门',
    ];
    return Padding(
      padding: EdgeInsets.only(
        left: widget.depth > 1 ? 12.0 : 0,
        bottom: widget.depth == 0 ? 10 : 0,
      ),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        tint: isDone ? Colors.green : null,
        tintAmount: 0.05,
        onTap: children.isEmpty ? null : () => setState(() => _open = !_open),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    g.name.isEmpty ? '未命名课组' : g.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  g.goal > 0
                      ? '${formatCredit(shownEarned)} / ${formatCredit(g.goal)}'
                      : formatCredit(shownEarned),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDone ? Colors.green : scheme.primary,
                  ),
                ),
                if (children.isNotEmpty)
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20)
                else
                  const SizedBox(width: 20),
              ],
            ),
            const SizedBox(height: 8),
            _CreditBar(
              earned: shownEarned,
              selected: inc ? 0 : sel,
              goal: g.goal,
              passed: isDone,
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (isShort)
                  '${inc ? '预计仍差' : '还差'} ${formatCredit(shownMissing)} 学分'
                else if (isDone)
                  (inc && g.short ? '本学期全过即修够' : '已修够'),
                ...details,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDone ? Colors.green : scheme.onSurfaceVariant,
              ),
            ),
            if (_open && children.isNotEmpty) ...[
              const SizedBox(height: 10),
              AdaptiveGrid(
                minColumnWidth: 320,
                maxColumns: 2,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in children)
                    _GroupCard(
                      key: ValueKey(c.id),
                      group: c,
                      depth: widget.depth + 1,
                      onlyShort: widget.onlyShort,
                      includeSelected: inc,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.error,
    required this.hasCache,
    required this.retry,
    required this.login,
  });
  final AppError error;
  final bool hasCache;
  final VoidCallback? retry;
  final VoidCallback login;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.onErrorContainer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error.message,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (error.hint != null) ...[
                const SizedBox(height: 8),
                Text(error.hint!),
              ],
              if (hasCache) ...[
                const SizedBox(height: 8),
                const Text('没刷新成功，下面是上次的数据。'),
              ],
              Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: retry, child: const Text('重试')),
                  if (error.kind == AppErrorKind.sessionExpired ||
                      error.kind == AppErrorKind.account)
                    TextButton(onPressed: login, child: const Text('重新登录')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry point for 成绩 / 我的: a one-line summary from the cached audit that
/// opens [DegreePage]. Hidden when the unified identity is signed out.
class DegreeProgressTile extends ConsumerWidget {
  const DegreeProgressTile({super.key, this.card = true});

  /// Wrap in a [GlassCard] (成绩 page); false gives a bare [ListTile] for
  /// settings-style lists.
  final bool card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(eduSessionProvider.select((s) => s.signedIn));
    if (!signedIn) return const SizedBox.shrink();
    final audit = ref.watch(degreeProvider.select((s) => s.audit));
    final plan = audit == null || audit.plans.isEmpty
        ? null
        : audit.plans.first;
    final tile = ListTile(
      contentPadding: card ? EdgeInsets.zero : null,
      leading: const Icon(Icons.insights_outlined),
      title: const Text('学业进度'),
      subtitle: Text(
        plan == null
            ? '培养方案里每类课修了多少学分'
            : plan.missing > 0
            ? '已修 ${formatCredit(plan.earned)} / ${formatCredit(plan.goal)} 学分，'
                  '还差 ${formatCredit(plan.missing)}'
            : '已修 ${formatCredit(plan.earned)} 学分，总学分已修够',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const DegreePage())),
    );
    if (!card) return tile;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: tile,
    );
  }
}
