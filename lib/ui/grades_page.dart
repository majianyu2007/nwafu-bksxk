import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../core/errors.dart';
import '../app/ui_prefs.dart';
import '../data/edu_models.dart';
import 'edu_login_page.dart';
import 'grades_trend.dart';
import 'widgets/glass.dart';
import 'widgets.dart';
import '../data/ics_export.dart';

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  String? _term;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = ref.read(eduSessionProvider);
      final grades = ref.read(gradesProvider);
      if (session.signedIn && grades.book == null && !grades.loading) {
        ref.read(gradesProvider.notifier).sync();
      }
    });
  }

  Future<void> _login() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const EduLoginPage()));
  }

  Future<void> _sync() async {
    if (!ref.read(eduSessionProvider).signedIn) {
      await _login();
      return;
    }
    await ref.read(gradesProvider.notifier).sync();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EduState>(eduSessionProvider, (previous, next) {
      if (next.account?.username != previous?.account?.username) {
        setState(() => _term = null);
      }
      if (next.signedIn &&
          (!((previous?.signedIn) ?? false) ||
              next.account?.username != previous?.account?.username)) {
        ref.read(gradesProvider.notifier).sync();
      }
    });
    final state = ref.watch(gradesProvider);
    final session = ref.watch(eduSessionProvider);
    final book = session.signedIn ? state.book : null;
    final theme = Theme.of(context);
    final terms = <String, String>{};
    for (final grade in book?.records ?? const <GradeRecord>[]) {
      terms[grade.termCode] = grade.termName.isEmpty
          ? grade.termCode
          : grade.termName;
    }
    final termCodes = terms.keys.toList()..sort((a, b) => b.compareTo(a));
    final selectedTerm = terms.containsKey(_term) ? _term : null;
    final records =
        [
          for (final record in book?.records ?? const <GradeRecord>[])
            if (selectedTerm == null || record.termCode == selectedTerm) record,
        ]..sort((a, b) {
          final byTerm = b.termCode.compareTo(a.termCode);
          return byTerm != 0 ? byTerm : a.courseName.compareTo(b.courseName);
        });
    final hidden = ref.watch(uiPrefsProvider.select((p) => p.hideGrades));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('成绩'),
        actions: [
          if (book != null)
            IconButton(
              tooltip: hidden ? '显示成绩' : '隐藏成绩',
              isSelected: hidden,
              onPressed: () =>
                  ref.read(uiPrefsProvider.notifier).setHideGrades(!hidden),
              icon: const Icon(Icons.visibility_outlined),
              selectedIcon: const Icon(Icons.visibility_off_outlined),
            ),
          if (book != null && book.records.isNotEmpty)
            IconButton(
              tooltip: '导出 CSV',
              onPressed: () async {
                try {
                  final r = await exportTextFile(
                    gradesCsv(book.records),
                    '成绩.csv',
                    ExportKind.csv,
                  );
                  if (!context.mounted) return;
                  if (r == IcsExportOutcome.saved ||
                      r == IcsExportOutcome.downloaded) {
                    showToast(context, '已导出成绩');
                  }
                } catch (_) {
                  if (context.mounted) showToast(context, '导出失败');
                }
              },
              icon: const Icon(Icons.file_download_outlined),
            ),
          if (session.signedIn)
            IconButton(
              tooltip: state.loading ? '正在同步成绩' : '同步成绩',
              onPressed: state.loading ? null : _sync,
              icon: const Icon(Icons.sync),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _sync,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '成绩',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            book == null
                                ? '登录后同步成绩，没网也能看。'
                                : session.account?.displayName ?? '',
                          ),
                          const SizedBox(height: 24),
                          if (!session.signedIn)
                            _GradesMessage(
                              icon: Icons.school_outlined,
                              title: '登录统一身份认证',
                              description: '用统一身份认证登录后查看成绩。',
                              actionLabel: '登录并同步',
                              onAction: _login,
                            )
                          else ...[
                            if (state.loading) ...[
                              const LinearProgressIndicator(
                                semanticsLabel: '正在同步成绩',
                              ),
                              const SizedBox(height: 12),
                              Text(
                                book == null
                                    ? '正在同步成绩…'
                                    : '正在更新…',
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (state.error != null) ...[
                              _GradesError(
                                error: state.error!,
                                hasCache: book != null,
                                retry: state.loading ? null : _sync,
                                login: _login,
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (book != null) ...[
                              _SummaryCards(
                                summary: book.summary,
                                hidden: hidden,
                              ),
                              if (GpaTrend.points(book.records).length >= 2)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: GlassCard(
                                    child: GpaTrend(
                                      records: book.records,
                                      hidden: hidden,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              const Text(
                                '绩点和排名为全部学期，来自教务系统。',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '上次同步：${_syncTime(context, book.syncedAt)}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 24),
                              DropdownButtonFormField<String>(
                                key: ValueKey(selectedTerm),
                                initialValue: selectedTerm ?? '__all__',
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: '学期',
                                  prefixIcon: Icon(Icons.filter_list),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '__all__',
                                    child: Text('全部学期'),
                                  ),
                                  for (final code in termCodes)
                                    DropdownMenuItem(
                                      value: code,
                                      child: Text(
                                        terms[code]!.isEmpty
                                            ? '未标注学期'
                                            : terms[code]!,
                                      ),
                                    ),
                                ],
                                onChanged: (value) => setState(
                                  () =>
                                      _term = value == '__all__' ? null : value,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${records.length} 条成绩记录',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              if (records.isEmpty)
                                const _GradesMessage(
                                  icon: Icons.receipt_long_outlined,
                                  title: '暂无成绩记录',
                                  description: '这个学期还没有成绩',
                                ),
                            ] else if (!state.loading && state.error == null)
                              _GradesMessage(
                                icon: Icons.cloud_download_outlined,
                                title: '还没有离线成绩',
                                description: '同步一次后，没网也能看。',
                                actionLabel: '同步成绩',
                                onAction: _sync,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: records.length,
                itemBuilder: (context, index) {
                  final grade = records[index];
                  final newTerm =
                      index == 0 ||
                      records[index - 1].termCode != grade.termCode;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (newTerm && selectedTerm == null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  bottom: 8,
                                ),
                                child: Text(
                                  grade.termName.isEmpty
                                      ? '未标注学期'
                                      : grade.termName,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                            GlassCard(
                              onTap: () => _showGrade(context, grade, hidden),
                              padding: EdgeInsets.zero,
                              radius: 16,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            grade.courseName.isEmpty
                                                ? '未命名课程'
                                                : grade.courseName,
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              '${_number(grade.credit)} 学分',
                                              if (grade.nature.isNotEmpty)
                                                grade.nature,
                                              if (grade.attempt.isNotEmpty)
                                                grade.attempt,
                                            ].join(' · '),
                                          ),
                                          if (!grade.passed)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: Text(
                                                '未通过',
                                                style: TextStyle(
                                                  color:
                                                      theme.colorScheme.error,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: HiddenValue(
                                        hidden: hidden,
                                        child: Text(
                                          grade.scoreText.isEmpty
                                              ? '未公布'
                                              : grade.scoreText,
                                          textAlign: TextAlign.end,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: grade.passed
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme.error,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 32 + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _syncTime(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatMediumDate(local)} ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary, required this.hidden});
  final GradeSummary summary;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = [
      ('平均学分绩点', summary.gpa, Icons.insights_outlined),
      ('加权平均成绩', summary.averageScore, Icons.assessment_outlined),
      ('专业排名', summary.majorRank, Icons.school_outlined),
      ('班级排名', summary.classRank, Icons.groups_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 320
            ? 2
            : 1;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: GlassCard(
                  tint: theme.colorScheme.primary,
                  tintAmount: 0.06,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(metric.$3, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      HiddenValue(
                        hidden: hidden,
                        child: Text(
                          metric.$2.isEmpty ? '未公布' : metric.$2,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(metric.$1),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GradesMessage extends StatelessWidget {
  const _GradesMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

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
        Text(description, textAlign: TextAlign.center),
        if (onAction != null) ...[
          const SizedBox(height: 16),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class _GradesError extends StatelessWidget {
  const _GradesError({
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
              Semantics(
                liveRegion: true,
                child: Text(
                  error.message,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (error.hint != null) ...[
                const SizedBox(height: 8),
                Text(error.hint!),
              ],
              if (hasCache) ...[
                const SizedBox(height: 8),
                const Text('更新失败，显示的是上次的成绩。'),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: retry, child: const Text('重新同步')),
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

void _showGrade(BuildContext context, GradeRecord grade, bool hidden) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Text(
            grade.courseName.isEmpty ? '课程详情' : grade.courseName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(grade.termName.isEmpty ? '未标注学期' : grade.termName),
          const SizedBox(height: 24),
          _GradeDetail(label: '总评成绩', value: hidden ? '已隐藏' : grade.scoreText),
          _GradeDetail(label: '是否通过', value: grade.passed ? '通过' : '未通过'),
          _GradeDetail(label: '学分', value: _number(grade.credit)),
          _GradeDetail(
            label: '绩点',
            value: hidden
                ? '已隐藏'
                : grade.gradePoint == null
                ? ''
                : _number(grade.gradePoint!),
          ),
          _GradeDetail(label: '课程代码', value: grade.courseCode),
          _GradeDetail(label: '课程性质', value: grade.nature),
          _GradeDetail(label: '课程类别', value: grade.category),
          _GradeDetail(label: '考核方式', value: grade.examType),
          _GradeDetail(label: '修读类型', value: grade.attempt),
          const Divider(height: 32),
          Text('分项成绩', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (grade.components.isEmpty)
            const Text('学校暂未提供分项成绩。')
          else
            for (final component in grade.components.entries)
              _GradeDetail(
                label: component.key,
                value: hidden ? '已隐藏' : component.value,
              ),
          const SizedBox(height: 24),
          const Text('以教务系统为准'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    ),
  );
}

class _GradeDetail extends StatelessWidget {
  const _GradeDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label)),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: SelectableText(
            value.isEmpty ? '未公布' : value,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
  );
}
