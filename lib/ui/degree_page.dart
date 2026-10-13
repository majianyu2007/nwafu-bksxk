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
import 'widgets/glass.dart';

String creditText(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class DegreePage extends ConsumerStatefulWidget {
  const DegreePage({super.key});

  @override
  ConsumerState<DegreePage> createState() => _DegreePageState();
}

class _DegreePageState extends ConsumerState<DegreePage> {
  bool _onlyShort = false;

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

  Future<void> _login() => Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => const EduLoginPage()));

  Future<void> _sync() async {
    if (!ref.read(eduSessionProvider).signedIn) {
      await _login();
      return;
    }
    await ref.read(degreeProvider.notifier).sync();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(eduSessionProvider);
    final state = ref.watch(degreeProvider);
    final audit = session.signedIn ? state.audit : null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('学业进度'),
        actions: [
          if (audit != null)
            IconButton(
              tooltip: _onlyShort ? '显示全部课组' : '只看没修够的',
              isSelected: _onlyShort,
              onPressed: () => setState(() => _onlyShort = !_onlyShort),
              icon: const Icon(Icons.filter_alt_outlined),
              selectedIcon: const Icon(Icons.filter_alt),
            ),
          if (session.signedIn)
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
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!session.signedIn)
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
                          _PlanHeader(plan: plan),
                          const SizedBox(height: 12),
                          for (final g in plan.groups)
                            if (!_onlyShort || g.short)
                              _GroupCard(
                                group: g,
                                depth: 0,
                                onlyShort: _onlyShort,
                              ),
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
    );
  }
}

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.plan});
  final DegreePlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = plan.selected ?? 0;
    final goal = plan.goal;
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
                  text: creditText(plan.earned),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                TextSpan(
                  text: ' / ${creditText(goal)} 学分',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CreditBar(
            earned: plan.earned,
            selected: selected,
            goal: goal,
            height: 12,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                plan.missing > 0
                    ? '还差 ${creditText(plan.missing)} 学分'
                    : '总学分已修够',
              ),
              if (plan.selected != null)
                Text('本学期已选 ${creditText(selected)} 学分'),
              Text('${(plan.progress * 100).toStringAsFixed(0)}%'),
            ],
          ),
          if (plan.computedAt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '学校计算于 ${plan.computedAt}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (plan.shortLeaves.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('还没修够', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in plan.shortLeaves)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.errorContainer,
                    side: BorderSide.none,
                    label: Text(
                      '${g.name} 差 ${creditText(g.missing)}',
                      style: TextStyle(color: scheme.onErrorContainer),
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
    this.short = false,
  });
  final double earned;
  final double selected;
  final double goal;
  final double height;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = goal <= 0 ? 1.0 : goal;
    final a = (earned / total).clamp(0.0, 1.0);
    final b = ((earned + selected) / total).clamp(0.0, 1.0);
    final color = goal > 0 && earned >= goal
        ? Colors.green
        : short
        ? scheme.error
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
    required this.group,
    required this.depth,
    required this.onlyShort,
  });
  final DegreeGroup group;
  final int depth;
  final bool onlyShort;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late bool _open = widget.depth == 0 && widget.group.short;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final children = [
      for (final c in g.children)
        if (!widget.onlyShort || c.short) c,
    ];
    final details = [
      if (g.nature.isNotEmpty) g.nature,
      if (g.selected != null && g.selected! > 0)
        '本学期已选 ${creditText(g.selected!)}',
      if (g.openCourses != null && g.openCourses! > 0)
        '本学期可选 ${g.openCourses} 门',
    ];
    return Padding(
      padding: EdgeInsets.only(left: widget.depth * 14.0, bottom: 8),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        tint: g.short ? scheme.error : null,
        tintAmount: 0.06,
        onTap: children.isEmpty ? null : () => setState(() => _open = !_open),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    g.name.isEmpty ? '未命名课组' : g.name,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  g.goal > 0
                      ? '${creditText(g.earned)} / ${creditText(g.goal)}'
                      : creditText(g.earned),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: g.short ? scheme.error : null,
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
              earned: g.earned,
              selected: g.selected ?? 0,
              goal: g.goal,
              short: g.short,
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (g.short)
                  '还差 ${creditText(g.missing)} 学分'
                else if (g.goal > 0 || g.passed)
                  '已修够',
                ...details,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: g.short ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            if (_open && children.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final c in children)
                _GroupCard(
                  group: c,
                  depth: 1,
                  onlyShort: widget.onlyShort,
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
            ? '已修 ${creditText(plan.earned)} / ${creditText(plan.goal)} 学分，'
                  '还差 ${creditText(plan.missing)}'
            : '已修 ${creditText(plan.earned)} 学分，总学分已修够',
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
