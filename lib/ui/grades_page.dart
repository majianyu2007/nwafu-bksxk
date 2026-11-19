import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../app/ui_prefs.dart';
import '../core/errors.dart';
import '../data/edu_models.dart';
import '../data/gpa_simulator.dart';
import '../data/ics_export.dart';
import 'degree_page.dart';
import 'edu_login_page.dart';
import 'gpa_simulator_sheet.dart';
import 'grades_trend.dart';
import 'layout.dart';
import 'widgets.dart';
import 'widgets/glass.dart';

enum _GradeSort { term, gpaDesc, creditDesc }

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  final _searchCtrl = TextEditingController();
  String? _term;
  String _query = '';
  String _natureFilter = '全部';
  _GradeSort _sort = _GradeSort.term;

  // Memoized projections of book.records to avoid re-sorting/re-aggregating on
  // unrelated rebuilds (e.g. toggling grade privacy blur).
  List<GradeRecord>? _cachedSource;
  Map<String, String> _cachedTerms = const {};
  List<String> _cachedTermCodes = const [];
  List<GpaPoint> _cachedTrendPoints = const [];
  String? _cachedFilterTerm;
  String _cachedFilterQuery = '';
  String _cachedFilterNature = '全部';
  _GradeSort _cachedFilterSort = _GradeSort.term;
  List<GradeRecord> _cachedRecords = const [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
    final ok = await pushEduLogin(context);
    if (ok == true && mounted && !ref.read(gradesProvider).loading) {
      await ref.read(gradesProvider.notifier).sync();
    }
  }

  Future<void> _sync() async {
    if (!ref.read(eduSessionProvider).signedIn) {
      await _login();
      return;
    }
    await ref.read(gradesProvider.notifier).sync();
  }

  void _ensureCache(List<GradeRecord> source) {
    final sourceChanged = !identical(_cachedSource, source);
    if (sourceChanged) {
      _cachedSource = source;
      final terms = <String, String>{};
      for (final grade in source) {
        terms[grade.termCode] = grade.termName.isEmpty
            ? grade.termCode
            : grade.termName;
      }
      _cachedTerms = terms;
      _cachedTermCodes = terms.keys.toList()..sort((a, b) => b.compareTo(a));
      _cachedTrendPoints = GpaTrend.points(source);
    }
    final selectedTerm = _cachedTerms.containsKey(_term) ? _term : null;
    if (sourceChanged ||
        _cachedFilterTerm != selectedTerm ||
        _cachedFilterQuery != _query ||
        _cachedFilterNature != _natureFilter ||
        _cachedFilterSort != _sort) {
      _cachedFilterTerm = selectedTerm;
      _cachedFilterQuery = _query;
      _cachedFilterNature = _natureFilter;
      _cachedFilterSort = _sort;
      final needle = _query.toLowerCase();
      _cachedRecords =
          [
            for (final record in source)
              if ((selectedTerm == null || record.termCode == selectedTerm) &&
                  (_natureFilter == '全部' ||
                      record.nature.contains(_natureFilter)) &&
                  (needle.isEmpty ||
                      record.courseName.toLowerCase().contains(needle)))
                record,
          ]..sort((a, b) {
            switch (_sort) {
              case _GradeSort.gpaDesc:
                final byGp = (b.gradePoint ?? -1).compareTo(a.gradePoint ?? -1);
                return byGp != 0 ? byGp : b.credit.compareTo(a.credit);
              case _GradeSort.creditDesc:
                final byCred = b.credit.compareTo(a.credit);
                return byCred != 0 ? byCred : b.termCode.compareTo(a.termCode);
              case _GradeSort.term:
                final byTerm = b.termCode.compareTo(a.termCode);
                return byTerm != 0
                    ? byTerm
                    : a.courseName.compareTo(b.courseName);
            }
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EduState>(eduSessionProvider, (previous, next) {
      if (next.account?.username != previous?.account?.username) {
        _searchCtrl.clear();
        setState(() {
          _term = null;
          _query = '';
          _natureFilter = '全部';
          _sort = _GradeSort.term;
        });
      }
      if (next.signedIn &&
          (!((previous?.signedIn) ?? false) ||
              next.account?.username != previous?.account?.username)) {
        ref.read(gradesProvider.notifier).sync();
      }
    });
    final state = ref.watch(gradesProvider);
    final signedIn = ref.watch(eduSessionProvider.select((s) => s.signedIn));
    final displayName = ref.watch(
      eduSessionProvider.select((s) => s.account?.displayName ?? ''),
    );
    final book = signedIn ? state.book : null;
    final theme = Theme.of(context);
    _ensureCache(book?.records ?? const <GradeRecord>[]);
    final terms = _cachedTerms;
    final termCodes = _cachedTermCodes;
    final trendPoints = _cachedTrendPoints;
    final selectedTerm = _cachedFilterTerm;
    final records = _cachedRecords;
    final hidden = ref.watch(uiPrefsProvider.select((p) => p.hideGrades));
    final showFilteredStats =
        !hidden &&
        records.isNotEmpty &&
        (selectedTerm != null || _natureFilter != '全部' || _query.isNotEmpty);
    final filteredSim = showFilteredStats
        ? simulateGpa(records: records)
        : null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('成绩'),
        actions: [
          if (book != null && book.records.isNotEmpty)
            IconButton(
              tooltip: 'GPA 模拟器与目标反推',
              onPressed: () => showAdaptiveSheet<void>(
                context,
                scrollControlled: true,
                maxWidth: 680,
                builder: (_) => GpaSimulatorSheet(
                  records: book.records,
                  hidden: hidden,
                  currentTermCredits: _estimateCurrentTermCredits(ref),
                ),
              ),
              icon: const Icon(Icons.calculate_outlined),
            ),
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
          if (signedIn)
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            book == null
                                ? '登录后同步成绩，没网也能看。'
                                : displayName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (!signedIn)
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
                              if (trendPoints.length >= 2)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: GlassCard(
                                    child: GpaTrend(
                                      records: book.records,
                                      precomputedPoints: trendPoints,
                                      hidden: hidden,
                                      onTermSelected: (code) => setState(() {
                                        _term = _term == code ? null : code;
                                      }),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              const DegreeProgressTile(),
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
                              const SizedBox(height: 12),
                              TextField(
                                controller: _searchCtrl,
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: const Icon(Icons.search, size: 18),
                                  hintText: '搜索课程名称',
                                  border: const OutlineInputBorder(),
                                  suffixIcon: _query.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: '清空',
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() => _query = '');
                                          },
                                        ),
                                ),
                                onChanged: (v) =>
                                    setState(() => _query = v.trim()),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (final n in const [
                                    '全部',
                                    '必修',
                                    '选修',
                                    '任选',
                                  ])
                                    ChoiceChip(
                                      label: Text(n),
                                      selected: _natureFilter == n,
                                      onSelected: (_) =>
                                          setState(() => _natureFilter = n),
                                    ),
                                  const SizedBox(width: 4),
                                  ChoiceChip(
                                    label: const Text('按学期'),
                                    selected: _sort == _GradeSort.term,
                                    onSelected: (_) =>
                                        setState(() => _sort = _GradeSort.term),
                                  ),
                                  ChoiceChip(
                                    label: const Text('按绩点'),
                                    selected: _sort == _GradeSort.gpaDesc,
                                    onSelected: (_) => setState(
                                      () => _sort = _GradeSort.gpaDesc,
                                    ),
                                  ),
                                  ChoiceChip(
                                    label: const Text('按学分'),
                                    selected: _sort == _GradeSort.creditDesc,
                                    onSelected: (_) => setState(
                                      () => _sort = _GradeSort.creditDesc,
                                    ),
                                  ),
                                ],
                              ),
                              if (filteredSim != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '当前筛选 ${records.length} 门 · '
                                  '${filteredSim.baseCredits.toStringAsFixed(1)} 学分 · '
                                  '均绩 ${filteredSim.baseGpa.toStringAsFixed(2)}'
                                  '${filteredSim.baseAverage != null ? ' · 加权 ${filteredSim.baseAverage!.toStringAsFixed(1)}' : ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Text(
                                '${records.length} 条成绩记录',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              if (records.isEmpty)
                                _GradesMessage(
                                  icon: Icons.receipt_long_outlined,
                                  title: '暂无成绩记录',
                                  description:
                                      (_query.isNotEmpty ||
                                              _natureFilter != '全部')
                                          ? '没有符合当前筛选条件的成绩'
                                          : selectedTerm != null
                                          ? '这个学期还没有成绩'
                                          : '还没有已公布的成绩',
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
                            if (newTerm &&
                                selectedTerm == null &&
                                _sort == _GradeSort.term)
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
                                              '${formatCredit(grade.credit)} 学分',
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
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 96,
                                      ),
                                      child: HiddenValue(
                                        hidden: hidden,
                                        child: Text(
                                          grade.scoreText.isEmpty
                                              ? '未公布'
                                              : grade.scoreText,
                                          textAlign: TextAlign.end,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
          _GradeDetail(label: '学分', value: formatCredit(grade.credit)),
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

double _estimateCurrentTermCredits(WidgetRef ref) {
  final tt = ref.read(timetableProvider).data;
  if (tt == null) return 20;
  final seen = <String, double>{};
  for (final s in tt.sessions) {
    if (s.custom || s.credit <= 0) continue;
    final key = s.courseCode.isNotEmpty ? s.courseCode : s.displayName;
    seen.putIfAbsent(key, () => s.credit);
  }
  for (final u in tt.unscheduled) {
    if (u.credit <= 0) continue;
    final key = u.code.isNotEmpty ? u.code : u.name;
    seen.putIfAbsent(key, () => u.credit);
  }
  final total = seen.values.fold<double>(0, (a, b) => a + b);
  return total > 0 ? total : 20;
}
