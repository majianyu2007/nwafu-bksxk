/// Courses page: kind tabs, search, and expandable course cards with per-class
/// grab / monitor actions.
///
/// On wide windows the page becomes master-detail: a course list on the left
/// and the selected course's teaching classes on the right, so a desktop user
/// never scrolls a stretched single column of expandable cards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';
import '../data/param_builders.dart';
import 'courses_controller.dart';
import 'layout.dart';
import 'teaching_class_tile.dart';
import 'widgets.dart';

/// Available width at which the course browser splits into list + detail.
const double _kMasterDetailBreakpoint = 1000;

class CoursesPage extends ConsumerStatefulWidget {
  const CoursesPage({super.key});

  @override
  ConsumerState<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends ConsumerState<CoursesPage> {
  final _searchCtrl = TextEditingController();

  /// Key of the course shown in the detail pane (wide layout only).
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(coursesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static String _keyOf(CourseRow row) {
    // QXKC wraps every teaching class as its own row, so the course number
    // alone is not unique there.
    final first = row.teachingClasses.isEmpty
        ? ''
        : row.teachingClasses.first.teachingClassId;
    return '${row.courseNumber}:$first';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coursesProvider);
    final ctrl = ref.read(coursesProvider.notifier);
    final batch = ref.watch(sessionProvider.select((s) => s.activeBatch));
    // Each round says which categories it exposes (display* flags); offer
    // only those, as the official tab bar does.
    final kinds = [
      for (final k in CourseKind.values)
        if (batch == null || batch.showsKind(k)) k,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kMasterDetailBreakpoint;
        return Column(
          children: [
            _Header(
              kind: state.kind,
              kinds: kinds,
              onKind: ctrl.setKind,
              searchCtrl: _searchCtrl,
              onSearch: (q) {
                ctrl.setQuery(q);
                ctrl.load();
              },
              onRefresh: state.loading ? null : ctrl.load,
              wide: wide,
            ),
            if (state.loading && state.rows.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (state.error != null && state.rows.isNotEmpty)
              MaterialBanner(
                content: Text('刷新失败：${state.error}'),
                actions: [
                  TextButton(onPressed: ctrl.load, child: const Text('重试')),
                ],
              ),
            Expanded(
              child: wide
                  ? _wideBody(context, state, ctrl, constraints.maxWidth)
                  : _compactBody(context, state, ctrl),
            ),
          ],
        );
      },
    );
  }

  /// Full-page placeholder for loading / error / empty states, or null when
  /// there are rows to show.
  Widget? _placeholder(CoursesState state, CoursesController ctrl) {
    if (state.loading && state.rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.rows.isEmpty) {
      return _ErrorState(message: state.error!, onRetry: ctrl.load);
    }
    if (!state.loadedOnce) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载课程…'),
          ],
        ),
      );
    }
    if (state.rows.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '没有找到课程',
        subtitle: '换一个课程类型或关键字试试。当前轮次可能未开放该类别。',
      );
    }
    return null;
  }

  Widget _compactBody(
      BuildContext context, CoursesState state, CoursesController ctrl) {
    final placeholder = _placeholder(state, ctrl);
    if (placeholder != null) return placeholder;
    return RefreshIndicator(
      onRefresh: ctrl.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        itemCount: state.rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) =>
            _CourseCard(row: state.rows[i], kind: state.kind),
      ),
    );
  }

  Widget _wideBody(BuildContext context, CoursesState state,
      CoursesController ctrl, double width) {
    final placeholder = _placeholder(state, ctrl);
    if (placeholder != null) return placeholder;

    final rows = state.rows;
    // Keep the selection if it still exists; otherwise fall back to the first
    // course so the detail pane is never blank while there is data.
    CourseRow? selected;
    for (final row in rows) {
      if (_keyOf(row) == _selectedKey) {
        selected = row;
        break;
      }
    }
    selected ??= rows.first;
    final selectedKey = _keyOf(selected);
    final listWidth = (width * 0.36).clamp(360.0, 520.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: listWidth,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final row = rows[i];
              final key = _keyOf(row);
              return _CourseListTile(
                row: row,
                selected: key == selectedKey,
                onTap: () => setState(() => _selectedKey = key),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _CourseDetailPane(
            key: ValueKey(selectedKey),
            row: selected,
            kind: state.kind,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.kind,
    required this.kinds,
    required this.onKind,
    required this.searchCtrl,
    required this.onSearch,
    required this.onRefresh,
    required this.wide,
  });

  final CourseKind kind;
  final List<CourseKind> kinds;
  final ValueChanged<CourseKind> onKind;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;
  final VoidCallback? onRefresh;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      controller: searchCtrl,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索课程名 / 课程号',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: '搜索',
          onPressed: () => onSearch(searchCtrl.text.trim()),
        ),
      ),
      onSubmitted: (q) => onSearch(q.trim()),
    );
    final chips = SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: wide ? 0 : 12),
        children: [
          for (final k in kinds)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(k.label),
                selected: k == kind,
                onSelected: (_) => onKind(k),
              ),
            ),
        ],
      ),
    );

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          PageHeader(
            title: '选课',
            actions: [
              IconButton(
                tooltip: '刷新课程列表',
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
              ),
            ],
          ),
          if (wide)
            // Search and category chips share one row; the search box stays a
            // sensible width instead of stretching across the whole window.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: search,
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: chips),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: search,
            ),
            const SizedBox(height: 10),
            chips,
          ],
          const SizedBox(height: 6),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// Grab / monitor / selection-prompt logic shared by the compact course card
/// and the wide detail pane, so both layouts behave identically.
mixin _CourseActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String? _busyClassId;

  /// The active round is a 预选 (volunteer) round.
  bool get _volunteerRound =>
      ref.read(sessionProvider).activeBatch?.isVolunteerRound ?? false;

  /// Asks which volunteer grade to file. Prefers the grades the server says
  /// this course still accepts (course/volunteer.do); when that list is empty
  /// (it is, for every course on this deployment) falls back to the global
  /// grade dictionary. Returns null when the user cancels.
  Future<String?> _pickVolunteerGrade(TeachingClass tc) async {
    final ctrl = ref.read(coursesProvider.notifier);
    var grades = <VolunteerGrade>[];
    try {
      grades = await ctrl.fetchVolunteerGrades(tc);
    } catch (_) {
      // Fall through to the global list.
    }
    if (grades.isEmpty) {
      try {
        grades = await ref.read(infoServiceProvider).fetchVolunteerGrades();
      } catch (_) {}
    }
    if (!mounted) return null;
    if (grades.isEmpty) {
      grades = [
        for (var i = 1; i <= 5; i++) VolunteerGrade(grade: '$i', name: '第$i志愿'),
      ];
    }
    return showAdaptiveSheet<String>(
      context,
      maxWidth: 420,
      builder: (context) => _VolunteerGradePicker(tc: tc, grades: grades),
    );
  }

  Future<void> _grab(TeachingClass tc) async {
    if (_busyClassId != null) return;
    final ctrl = ref.read(coursesProvider.notifier);
    final volunteer = _volunteerRound;
    if (tc.isConflict) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('课程时间冲突'),
          content: Text(tc.conflictDesc.isNotEmpty
              ? '该教学班与已选课程冲突：\n${tc.conflictDesc}\n\n学校系统通常会拒绝冲突的选课；仍要提交吗？'
              : '该教学班与已选课程存在时间冲突。学校系统通常会拒绝冲突的选课；仍要提交吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('仍要提交')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    String? grade;
    if (volunteer) {
      grade = await _pickVolunteerGrade(tc);
      if (grade == null || !mounted) return;
    }
    setState(() => _busyClassId = tc.teachingClassId);
    try {
      final selections = await _resolveSelectionsIfNeeded(tc);
      if (selections == null) return;
      final (testId, book) = selections;
      final outcome = await ctrl.grabNow(tc,
          testTeachingClassId: testId,
          bookSelection: book,
          volunteerGrade: grade);
      if (!mounted) return;
      if (outcome.success) {
        showToast(context, outcome.message, success: true);
      } else {
        // Classify so a rule (already holds the course, conflict, capacity)
        // reads as a rule and not as a generic failure.
        final err = AppError.fromBusiness(outcome.code, outcome.message);
        showToast(
          context,
          err.hint != null ? '${err.message}\n${err.hint}' : err.message,
          success: false,
        );
      }
    } on MissingSelectionError catch (e) {
      if (mounted) showToast(context, e.reason, success: false);
    } catch (e) {
      if (mounted) showToast(context, '$e', success: false);
    } finally {
      if (mounted) setState(() => _busyClassId = null);
    }
  }

  Future<void> _monitor(TeachingClass tc) async {
    if (_busyClassId != null) return;
    final ctrl = ref.read(coursesProvider.notifier);
    var allowConflict = false;
    if (tc.isConflict) {
      // A conflicting class is polled but never submitted unless the user
      // explicitly opts in; say so up front instead of watching forever.
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('该教学班与已选课程冲突'),
          content: Text(
            '${tc.conflictDesc.isNotEmpty ? '${tc.conflictDesc}\n\n' : ''}'
            '空位出现时是否仍然自动提交？学校系统通常会拒绝冲突的选课，除非你先退掉冲突的课程。',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('只监控，不提交')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('有空位就提交')),
          ],
        ),
      );
      if (proceed == null || !mounted) return;
      allowConflict = proceed;
    }
    String? grade;
    if (_volunteerRound) {
      grade = await _pickVolunteerGrade(tc);
      if (grade == null || !mounted) return;
    }
    setState(() => _busyClassId = tc.teachingClassId);
    try {
      final selections = await _resolveSelectionsIfNeeded(tc);
      if (selections == null) return;
      final (testId, book) = selections;
      final watch = ctrl.addToMonitor(tc,
          testTeachingClassId: testId,
          bookSelection: book,
          volunteerGrade: grade,
          allowConflict: allowConflict);
      if (!mounted) return;
      final needsSetup = watch.status == WatchStatus.needsSetup;
      showToast(
        context,
        needsSetup ? '已加入监控，但仍需完成实验课/教材选择' : '已加入监控：${tc.courseName}',
        success: !needsSetup,
      );
    } catch (e) {
      if (mounted) showToast(context, '$e', success: false);
    } finally {
      if (mounted) setState(() => _busyClassId = null);
    }
  }

  /// Prompts for every required experiment/textbook choice. A null result means
  /// the user cancelled, so callers must not submit or create an incomplete watch.
  Future<(String?, String?)?> _resolveSelectionsIfNeeded(
      TeachingClass tc) async {
    String? testId;
    String? book;
    if (tc.hasTest && tc.testTeachingClassId.isEmpty) {
      testId = await _pickTestClass(tc);
      if (testId == null || testId.isEmpty) return null;
    } else if (tc.hasTest) {
      testId = tc.testTeachingClassId;
    }
    // The official page only asks about textbooks when the round has
    // ordering open (batch canSelectBook); otherwise needBook is not sent.
    final orderingOpen =
        ref.read(sessionProvider).activeBatch?.canSelectBook ?? true;
    if (tc.hasBook && orderingOpen) {
      final sel = await _promptTextbookSelection(tc);
      if (sel == null) return null;
      book = sel.jcxx;
      if (book.isEmpty) book = null;
    }
    return (testId, book);
  }

  Future<String?> _pickTestClass(TeachingClass tc) async {
    final ctrl = ref.read(coursesProvider.notifier);
    final list = await ctrl.fetchTestCourses(tc);
    if (!mounted) return null;
    if (list.isEmpty) {
      showToast(context, '未获取到可选实验教学班', success: false);
      return null;
    }
    final selected = await showAdaptiveSheet<String>(
      context,
      builder: (context) => TestClassPicker(list: list),
    );
    if (selected != null && selected.isNotEmpty && mounted) {
      showToast(context, '实验教学班已选择');
    }
    return selected;
  }

  Future<TextbookSelection?> _promptTextbookSelection(TeachingClass tc) async {
    final session = ref.read(sessionProvider);
    final student = session.student;
    final batch = session.activeBatch;
    if (student == null || batch == null) return null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    try {
      final course = ref.read(courseServiceProvider);
      final info = ref.read(infoServiceProvider);
      final results = await Future.wait([
        course.fetchTextbookOptions(
          studentCode: student.studentCode,
          batchCode: batch.code,
          teachingClassId: tc.teachingClassId,
        ),
        // Decline reasons live in the dictionary, not on the rows.
        info.fetchTextbookReasons(),
      ]);
      final reasons = results[1] as List<TextbookReason>;
      final options = [
        for (final o in results[0] as List<TextbookOption>)
          o.copyWith(reasonCodes: reasons),
      ];
      if (!mounted) return null;
      Navigator.of(context).pop();
      if (options.isEmpty) {
        showToast(context, '未获取到教材清单，按默认提交');
        return TextbookSelection(tc.needBook.isNotEmpty ? tc.needBook : '', []);
      }
      final selection = await showAdaptiveSheet<TextbookSelection>(
        context,
        scrollControlled: true,
        builder: (context) => TextbookPicker(options: options),
      );
      if (selection == null && mounted) {
        showToast(context, '已取消教材选择', success: false);
      }
      return selection;
    } catch (_) {
      if (!mounted) return null;
      Navigator.of(context).pop();
      showToast(context, '获取教材信息失败', success: false);
      return null;
    }
  }
}

/// One course in the wide layout's list pane.
class _CourseListTile extends StatelessWidget {
  const _CourseListTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final CourseRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final classes = row.teachingClasses;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.courseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                        if (row.selected) ...[
                          const SizedBox(width: 8),
                          const StatusPill(
                              label: '已选',
                              color: Colors.green,
                              icon: Icons.check),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _meta(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${classes.length}个班',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              Icon(Icons.chevron_right,
                  size: 18,
                  color:
                      selected ? scheme.onSecondaryContainer : scheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  static String _meta(CourseRow row) => [
        row.courseNumber,
        if (row.credit.isNotEmpty) '${row.credit}学分',
        if (row.courseNatureName.isNotEmpty) row.courseNatureName,
        if (row.departmentName.isNotEmpty) row.departmentName,
      ].join(' · ');
}

/// The wide layout's right pane: the selected course's teaching classes, laid
/// out in one or two columns depending on the pane width.
class _CourseDetailPane extends ConsumerStatefulWidget {
  const _CourseDetailPane({super.key, required this.row, required this.kind});
  final CourseRow row;
  final CourseKind kind;

  @override
  ConsumerState<_CourseDetailPane> createState() => _CourseDetailPaneState();
}

class _CourseDetailPaneState extends ConsumerState<_CourseDetailPane>
    with _CourseActions<_CourseDetailPane> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = widget.row;
    final classes = row.teachingClasses;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 24, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                row.courseName,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (row.selected)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 4),
                child: StatusPill(
                    label: '已选', color: Colors.green, icon: Icons.check),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            _CourseListTile._meta(row),
            '${classes.length}个教学班',
          ].join(' · '),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (classes.isEmpty)
          const EmptyState(icon: Icons.class_outlined, title: '该课程暂无教学班')
        else
          AdaptiveGrid(
            minColumnWidth: 440,
            maxColumns: 2,
            children: [
              for (final tc in classes)
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: TeachingClassTile(
                    teachingClass: tc,
                    kind: widget.kind,
                    bordered: false,
                    browseOnly: widget.kind == CourseKind.qxkc,
                    volunteerRound: _volunteerRound,
                    courseAlreadyHeld: row.selected && !tc.isChoose,
                    onGrab: () => _grab(tc),
                    onMonitor: () => _monitor(tc),
                    onRefresh: () =>
                        ref.read(coursesProvider.notifier).refresh(tc),
                    busy: _busyClassId == tc.teachingClassId,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _CourseCard extends ConsumerStatefulWidget {
  const _CourseCard({required this.row, required this.kind});
  final CourseRow row;
  final CourseKind kind;

  @override
  ConsumerState<_CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends ConsumerState<_CourseCard>
    with _CourseActions<_CourseCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = widget.row;
    final classes = row.teachingClasses;

    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: classes.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                row.courseName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                            if (row.selected) ...[
                              const SizedBox(width: 8),
                              const StatusPill(
                                  label: '已选',
                                  color: Colors.green,
                                  icon: Icons.check),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _CourseListTile._meta(row),
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (classes.isNotEmpty)
                    Row(
                      children: [
                        Text('${classes.length}个班',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                            color: scheme.onSurfaceVariant),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (final tc in classes)
              TeachingClassTile(
                teachingClass: tc,
                kind: widget.kind,
                browseOnly: widget.kind == CourseKind.qxkc,
                volunteerRound: _volunteerRound,
                courseAlreadyHeld: row.selected && !tc.isChoose,
                onGrab: () => _grab(tc),
                onMonitor: () => _monitor(tc),
                onRefresh: () => ref.read(coursesProvider.notifier).refresh(tc),
                busy: _busyClassId == tc.teachingClassId,
              ),
        ],
      ),
    );
  }
}

/// 预选: pick the volunteer grade to file for [tc].
class _VolunteerGradePicker extends StatelessWidget {
  const _VolunteerGradePicker({required this.tc, required this.grades});
  final TeachingClass tc;
  final List<VolunteerGrade> grades;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('填报志愿', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('${tc.courseName} · ${tc.displayTitle}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            '预选按志愿顺序录取，第一志愿优先；同一课程只能填报一个教学班。',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final g in grades)
            ListTile(
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: g.grade == '1'
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                child: Text(g.grade,
                    style: TextStyle(
                        color: g.grade == '1'
                            ? scheme.onPrimary
                            : scheme.onSurface,
                        fontWeight: FontWeight.w700)),
              ),
              title: Text(g.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(g.grade),
            ),
        ],
      ),
    );
  }
}

class TestClassPicker extends StatelessWidget {
  const TestClassPicker({super.key, required this.list});
  final List<Map<String, dynamic>> list;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('选择实验教学班', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final item in list)
            ListTile(
              title: Text(
                  '${item['courseName'] ?? item['teachingClassName'] ?? '实验班'}'),
              subtitle: Text(
                  '${item['teacherName'] ?? ''}  ${item['teachingPlace'] ?? ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final id = testTeachingClassIdFromRow(item);
                if (id != null) Navigator.of(context).pop(id);
              },
            ),
        ],
      ),
    );
  }
}

class TextbookPicker extends StatefulWidget {
  const TextbookPicker({super.key, required this.options});
  final List<TextbookOption> options;

  @override
  State<TextbookPicker> createState() => _TextbookPickerState();
}

class _TextbookPickerState extends State<TextbookPicker> {
  late List<bool> _ordered;
  late List<String> _reasonCodes;

  @override
  void initState() {
    super.initState();
    _ordered = List.generate(
        widget.options.length, (i) => widget.options[i].orderable);
    _reasonCodes = List.generate(widget.options.length, (_) => '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text('选择教材', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: widget.options.length,
                itemBuilder: (context, i) {
                  final book = widget.options[i];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        title: Text(book.bookName),
                        subtitle: Text([
                          if (book.isbn.isNotEmpty) 'ISBN:${book.isbn}',
                          if (book.press.isNotEmpty) book.press,
                          '¥${book.price}',
                        ].join(' · ')),
                        value: _ordered[i],
                        enabled: book.orderable,
                        onChanged: book.orderable
                            ? (value) => setState(() {
                                  _ordered[i] = value ?? true;
                                  if (!_ordered[i] &&
                                      _reasonCodes[i].isEmpty &&
                                      book.reasonCodes.isNotEmpty) {
                                    _reasonCodes[i] =
                                        book.reasonCodes.first.code;
                                  }
                                })
                            : null,
                      ),
                      if (!_ordered[i] && book.reasonCodes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 16, right: 16, bottom: 8),
                          child: DropdownButtonFormField<String>(
                            initialValue: _reasonCodes[i].isNotEmpty
                                ? _reasonCodes[i]
                                : null,
                            decoration: const InputDecoration(
                              labelText: '不订购原因',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              isDense: true,
                            ),
                            items: book.reasonCodes
                                .map((reason) => DropdownMenuItem(
                                      value: reason.code,
                                      child: Text(reason.name),
                                    ))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _reasonCodes[i] = value ?? ''),
                          ),
                        ),
                      if (!book.orderable)
                        Padding(
                          padding: const EdgeInsets.only(left: 72, bottom: 8),
                          child: Text(
                            '该教材不可订购',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check),
                label: const Text('确认教材选择'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirm() {
    final choices = <BookChoice>[];
    for (var i = 0; i < widget.options.length; i++) {
      final book = widget.options[i];
      if (_ordered[i]) {
        choices.add(BookChoice(bookCode: book.bookCode, order: true));
      } else {
        final reason = _reasonCodes[i].trim();
        if (reason.isEmpty || reason == '***') {
          showToast(context, '请选择「${book.bookName}」的不订购原因', success: false);
          return;
        }
        choices.add(BookChoice(
          bookCode: book.bookCode,
          order: false,
          reasonCode: reason,
        ));
      }
    }
    final jcxx = buildBookSelection(choices);
    Navigator.pop(context, TextbookSelection(jcxx, choices));
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
