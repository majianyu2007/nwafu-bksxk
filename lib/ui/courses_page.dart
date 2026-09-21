/// Courses page: category tabs, search, filters, and course cards with
/// per-class grab / monitor actions. On wide windows it is master-detail: the
/// course list on the left and the selected course's classes on the right.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import '../app/providers.dart';
import '../core/constants.dart';
import '../core/errors.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';
import '../data/param_builders.dart';
import 'courses_controller.dart';
import 'home_page.dart' show creditInfoProvider;
import 'layout.dart';
import 'teaching_class_tile.dart';
import 'widgets.dart';

/// Available width at which the course browser splits into list + detail.
const double _kMasterDetailBreakpoint = 1000;

/// The shown account's courses controller.
final coursesProvider = Provider<CoursesController>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) throw StateError('no account is signed in');
  return ref.watch(coursesOfProvider(id).notifier);
});

final coursesStateProvider = Provider<CoursesState>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) return CoursesState();
  return ref.watch(coursesOfProvider(id));
});

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
      if (!mounted) return;
      final state = ref.read(coursesStateProvider);
      _searchCtrl.text = state.query;
      if (!state.loadedOnce && !state.loading) ref.read(coursesProvider).load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static String _keyOf(CourseRow row) => row.courseNumber;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coursesStateProvider);
    final ctrl = ref.read(coursesProvider);
    final batch = ref.watch(sessionProvider.select((s) => s.activeBatch));
    final sysParams =
        ref.watch(sysParamsProvider).asData?.value ?? SysParams.empty;
    // Each round says which categories it exposes (display* flags); offer
    // only those, as the official tab bar does.
    final kinds = [
      for (final k in CourseKind.values)
        if (batch == null || batch.showsKind(k)) k,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >=
            _kMasterDetailBreakpoint * layoutTextScale(context);
        return Column(
          children: [
            _Header(
              kind: state.kind,
              kinds: kinds,
              labelOf: sysParams.tabName,
              onKind: ctrl.setKind,
              searchCtrl: _searchCtrl,
              onSearch: (q) {
                ctrl.setQuery(q);
                if (!state.paged) ctrl.load();
              },
              onRefresh: state.loading ? null : ctrl.refreshCatalogOrCourses,
              wide: wide,
            ),
            if (state.kind == CourseKind.xgxk) const _CreditRequirementStrip(),
            if (state.rows.isNotEmpty || state.paged)
              _FilterBar(state: state, ctrl: ctrl),
            if (state.paged)
              NoticeStrip(
                icon: state.catalogComplete
                    ? Icons.offline_pin_outlined
                    : Icons.download_outlined,
                text: state.loading
                    ? '正在后台下载目录：${state.catalogDownloaded}'
                        '${state.totalCount > 0 ? ' / ${state.totalCount}' : ''} 个班'
                        '${state.catalogComplete ? '；继续使用原完整缓存' : '；已下载部分可搜索'}'
                    : state.catalogComplete
                        ? '完整目录已保存本机${state.cachedAt == null ? '' : '（${_ago(state.cachedAt!)}）'}；搜索和翻页无需联网'
                        : '目录尚未完整：已保存 ${state.catalogDownloaded} 个班；搜索仅覆盖已下载部分',
                action: state.loading
                    ? null
                    : TextButton(
                        onPressed: ctrl.refreshCatalogOrCourses,
                        child: Text(state.catalogComplete ? '更新目录' : '继续下载'),
                      ),
              ),
            if (state.loading && state.rows.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (!state.paged && state.cachedAt != null)
              NoticeStrip(
                icon: Icons.history,
                text: state.loading
                    ? '显示的是 ${_ago(state.cachedAt!)}的缓存，正在刷新'
                    : '显示的是 ${_ago(state.cachedAt!)}的缓存，刷新失败',
              ),
            if (state.error != null && state.rows.isNotEmpty)
              NoticeStrip(
                icon: Icons.cloud_off_outlined,
                error: true,
                text: '刷新失败：${state.error}',
                action: TextButton(
                    onPressed: ctrl.refreshCatalogOrCourses,
                    child: const Text('重试')),
              ),
            Expanded(
              child: wide
                  ? _wideBody(context, state, ctrl, constraints.maxWidth)
                  : _compactBody(context, state, ctrl),
            ),
            if (state.paged && state.pageCount > 1)
              _Pager(state: state, onPage: ctrl.goToPage),
          ],
        );
      },
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚才';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  /// Full-page placeholder for loading / error / empty states, or null when
  /// there are rows to show.
  Widget? _placeholder(CoursesState state, CoursesController ctrl) {
    if (state.loading && state.rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.rows.isEmpty) {
      return _ErrorState(
          message: state.error!, onRetry: ctrl.refreshCatalogOrCourses);
    }
    if (!state.loadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.rows.isEmpty) {
      return const EmptyState(icon: Icons.search_off, title: '没有课程');
    }
    if (state.visibleRows.isEmpty) {
      return const EmptyState(
          icon: Icons.filter_alt_off_outlined, title: '筛选后没有课程');
    }
    return null;
  }

  Widget _compactBody(
      BuildContext context, CoursesState state, CoursesController ctrl) {
    final placeholder = _placeholder(state, ctrl);
    if (placeholder != null) return placeholder;
    final rows = state.visibleRows;
    return RefreshIndicator(
      onRefresh: ctrl.refreshCatalogOrCourses,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) =>
            _CourseCard(row: rows[i], kind: state.kind),
      ),
    );
  }

  Widget _wideBody(BuildContext context, CoursesState state,
      CoursesController ctrl, double width) {
    final placeholder = _placeholder(state, ctrl);
    if (placeholder != null) return placeholder;

    final rows = state.visibleRows;
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
    required this.labelOf,
    required this.onKind,
    required this.searchCtrl,
    required this.onSearch,
    required this.onRefresh,
    required this.wide,
  });

  final CourseKind kind;
  final List<CourseKind> kinds;
  final String Function(CourseKind) labelOf;
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
        hintText: kind.isBrowseOnly ? '本地搜索课程名、课程号或教师' : '课程名或课程号',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: '搜索',
          onPressed: () => onSearch(searchCtrl.text.trim()),
        ),
      ),
      onChanged: kind.isBrowseOnly ? onSearch : null,
      onSubmitted: (q) => onSearch(q.trim()),
    );
    final chips = SizedBox(
      height: 32 + MediaQuery.textScalerOf(context).scale(20),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: wide ? 0 : 12),
        children: [
          for (final k in kinds)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(labelOf(k)),
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
                tooltip: kind.isBrowseOnly ? '更新完整目录' : '刷新',
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
              ),
            ],
          ),
          if (wide)
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

  CoursesController get _ctrl => ref.read(coursesProvider);

  /// The active round is a 预选 (volunteer) round.
  bool get _volunteerRound =>
      ref.read(sessionProvider).activeBatch?.isVolunteerRound ?? false;

  /// Asks which volunteer grade to file. Prefers the grades the server says
  /// this course still accepts (course/volunteer.do); when that list is empty
  /// (it is, for every course on this deployment) falls back to the global
  /// grade dictionary. Returns null when the user cancels.
  Future<String?> _pickVolunteerGrade(TeachingClass tc) async {
    var grades = <VolunteerGrade>[];
    try {
      grades = await _ctrl.fetchVolunteerGrades(tc);
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

  Future<bool> _confirmConflict(TeachingClass tc,
      {required bool monitor}) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('时间冲突'),
        content: Text(
          '${tc.conflictDesc.isNotEmpty ? '${tc.conflictDesc}\n\n' : ''}'
          '学校系统一般会拒绝有冲突的选课，除非先退掉冲突的课程。'
          '${monitor ? '\n\n有空位时是否仍然提交？' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(monitor ? '只监控不提交' : '取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(monitor ? '有空位就提交' : '仍要提交')),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _grab(TeachingClass tc) async {
    if (_busyClassId != null) return;
    if (tc.isConflict && !await _confirmConflict(tc, monitor: false)) return;
    if (!mounted) return;
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
      final outcome = await _ctrl.grabNow(tc,
          testTeachingClassId: testId,
          bookSelection: book,
          volunteerGrade: grade);
      if (!mounted) return;
      if (outcome.success) {
        showToast(context, outcome.message, success: true);
      } else {
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

  Future<void> _toggleMonitor(TeachingClass tc, {required bool watched}) async {
    if (_busyClassId != null) return;
    if (watched) {
      _ctrl.removeFromMonitor(tc);
      showToast(context, '已取消监控：${tc.courseName}');
      return;
    }
    var allowConflict = false;
    if (tc.isConflict) {
      // A conflicting class is polled but never submitted unless the user
      // opts in; ask up front instead of watching forever.
      allowConflict = await _confirmConflict(tc, monitor: true);
      if (!mounted) return;
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
      final watch = _ctrl.addToMonitor(tc,
          testTeachingClassId: testId,
          bookSelection: book,
          volunteerGrade: grade,
          allowConflict: allowConflict);
      if (!mounted) return;
      final needsSetup = watch.status == WatchStatus.needsSetup;
      showToast(
        context,
        needsSetup ? '已加入监控，还需完成实验课或教材选择' : '已加入监控：${tc.courseName}',
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
    final list = await _ctrl.fetchTestCourses(tc);
    if (!mounted) return null;
    if (list.isEmpty) {
      showToast(context, '没有可选的实验教学班', success: false);
      return null;
    }
    return showAdaptiveSheet<String>(
      context,
      builder: (context) => TestClassPicker(list: list),
    );
  }

  Future<TextbookSelection?> _promptTextbookSelection(TeachingClass tc) async {
    final session = ref.read(sessionProvider);
    final student = session.student;
    final batch = session.activeBatch;
    if (student == null || batch == null) return null;
    try {
      final course = ref.read(courseServiceProvider);
      final info = ref.read(infoServiceProvider);
      final results = await Future.wait([
        course.fetchTextbookOptions(
          studentCode: student.studentCode,
          batchCode: batch.code,
          teachingClassId: tc.teachingClassId,
        ),
        info.fetchTextbookReasons(),
      ]);
      final reasons = results[1] as List<TextbookReason>;
      final options = [
        for (final o in results[0] as List<TextbookOption>)
          o.copyWith(reasonCodes: reasons),
      ];
      if (!mounted) return null;
      if (options.isEmpty) {
        return TextbookSelection(tc.needBook.isNotEmpty ? tc.needBook : '', []);
      }
      return showAdaptiveSheet<TextbookSelection>(
        context,
        scrollControlled: true,
        builder: (context) => TextbookPicker(options: options),
      );
    } catch (_) {
      if (mounted) showToast(context, '获取教材信息失败', success: false);
      return null;
    }
  }

  Future<void> _checkCanChoose(TeachingClass tc) async {
    final session = ref.read(sessionProvider);
    final student = session.student;
    final batch = session.activeBatch;
    if (student == null || batch == null) return;
    List<String> reasons;
    try {
      reasons = await ref.read(courseServiceProvider).fetchCanChooseReasons(
            studentCode: student.studentCode,
            teachingClassId: tc.teachingClassId,
            batchCode: batch.code,
          );
    } catch (e) {
      if (mounted) showToast(context, '$e', success: false);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tc.courseName} ${tc.displayTitle}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(r),
              ),
            if (reasons.isEmpty) const Text('服务器没有给出原因'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _tile(TeachingClass tc, CourseRow row, CourseKind kind,
      {bool bordered = true}) {
    final watched = ref.watch(watchesProvider).any(
        (w) => w.id == _ctrl.watchIdFor(tc) && w.status != WatchStatus.grabbed);
    return TeachingClassTile(
      teachingClass: tc,
      kind: kind,
      bordered: bordered,
      browseOnly: kind.isBrowseOnly,
      volunteerRound: _volunteerRound,
      courseAlreadyHeld: row.isHeld && !tc.isHeld,
      watched: watched,
      onGrab: () => _grab(tc),
      onMonitor: () => _toggleMonitor(tc, watched: watched),
      onRefresh: () => _ctrl.refresh(tc),
      onCheck: kind.isBrowseOnly ? () => _checkCanChoose(tc) : null,
      busy: _busyClassId == tc.teachingClassId,
    );
  }
}

/// Course-level summary line: number, credit, category, department.
String courseMeta(CourseRow row) => [
      row.courseNumber,
      if (row.credit.isNotEmpty) '${row.credit} 学分',
      if (row.publicCourseType.isNotEmpty)
        row.publicCourseType
      else if (row.courseNatureName.isNotEmpty)
        row.courseNatureName,
      if (row.departmentName.isNotEmpty) row.departmentName,
    ].join('  ');

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
    final open =
        classes.where((c) => !c.hasCapacityInfo || c.remaining > 0).length;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                        if (row.onlinePlatform.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          StatusPill(
                              label: row.onlinePlatform, color: Colors.teal),
                        ],
                        if (row.isHeld) ...[
                          const SizedBox(width: 6),
                          const StatusPill(
                              label: '已选',
                              color: Colors.green,
                              icon: Icons.check),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      courseMeta(row),
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
                classes.first.hasCapacityInfo
                    ? '$open/${classes.length} 班可选'
                    : '${classes.length} 班',
                style: TextStyle(
                    color: open == 0 && classes.first.hasCapacityInfo
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontSize: 12),
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
}

/// The wide layout's right pane: the selected course's teaching classes.
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
            if (row.isHeld)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 4),
                child: StatusPill(
                    label: '已选', color: Colors.green, icon: Icons.check),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${courseMeta(row)}  ${classes.length} 个教学班',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (classes.isEmpty)
          const EmptyState(icon: Icons.class_outlined, title: '没有教学班')
        else
          AdaptiveGrid(
            minColumnWidth: 440,
            maxColumns: 2,
            children: [
              for (final tc in classes)
                Card(child: _tile(tc, row, widget.kind, bordered: false)),
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
    final open =
        classes.where((c) => !c.hasCapacityInfo || c.remaining > 0).length;

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
                            if (row.onlinePlatform.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              StatusPill(
                                  label: row.onlinePlatform,
                                  color: Colors.teal),
                            ],
                            if (row.isHeld) ...[
                              const SizedBox(width: 6),
                              const StatusPill(
                                  label: '已选',
                                  color: Colors.green,
                                  icon: Icons.check),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          courseMeta(row),
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (classes.isNotEmpty)
                    Row(
                      children: [
                        Text(
                            classes.first.hasCapacityInfo
                                ? '$open/${classes.length} 班可选'
                                : '${classes.length} 班',
                            style: TextStyle(
                                color:
                                    open == 0 && classes.first.hasCapacityInfo
                                        ? scheme.error
                                        : scheme.onSurfaceVariant,
                                fontSize: 12)),
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                            color: scheme.onSurfaceVariant),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (final tc in classes) _tile(tc, row, widget.kind),
        ],
      ),
    );
  }
}

/// The 通识 tab's credit requirements per category, the text the official
/// page shows above the 通识 list (studentInfo.spCourseDescription).
class _CreditRequirementStrip extends ConsumerWidget {
  const _CreditRequirementStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final credit = ref.watch(creditInfoProvider).asData?.value;
    final reqs = credit?.requirements ?? const [];
    if (reqs.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 24 + MediaQuery.textScalerOf(context).scale(20),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: reqs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = reqs[i];
          return Tooltip(
            message: '${r.category}\n要求学分 ${r.required}，已修 ${r.earned}',
            child: Chip(
              visualDensity: VisualDensity.compact,
              label: Text(
                  '${r.category.replaceAll('-2025版', '')}  ${r.earned}/${r.required}',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          );
        },
      ),
    );
  }
}

/// Local facets for downloaded courses, with enrollment-only switches hidden
/// for the query-only whole-school catalogue.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.state, required this.ctrl});
  final CoursesState state;
  final CoursesController ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = state.filters;
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[];
    final types = state.publicTypes;
    final departments = state.departments;
    if (types.length > 1) {
      chips.add(_FacetMenu(
        label: '类别',
        value: f.publicType,
        options: types,
        onChanged: (v) => ctrl.setFilters(f.copyWith(publicType: v)),
      ));
    }
    if (departments.length > 1) {
      chips.add(_FacetMenu(
        label: '开课单位',
        value: f.department,
        options: departments,
        onChanged: (v) => ctrl.setFilters(f.copyWith(department: v)),
      ));
    }
    if (!state.paged) {
      chips.addAll([
        FilterChip(
          label: const Text('无冲突'),
          selected: f.hideConflict,
          onSelected: (v) => ctrl.setFilters(f.copyWith(hideConflict: v)),
        ),
        FilterChip(
          label: const Text('有余量'),
          selected: f.onlyAvailable,
          onSelected: (v) => ctrl.setFilters(f.copyWith(onlyAvailable: v)),
        ),
      ]);
    }
    if (state.hasOnline) {
      chips.add(FilterChip(
        label: const Text('网课'),
        selected: f.onlyOnline,
        onSelected: (v) => ctrl.setFilters(f.copyWith(onlyOnline: v)),
      ));
    }
    if (f.isActive) {
      chips.add(ActionChip(
        avatar: const Icon(Icons.clear, size: 16),
        label: const Text('清除'),
        onPressed: () => ctrl.setFilters(const CourseFilters()),
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    final classCount =
        state.visibleRows.fold<int>(0, (n, r) => n + r.teachingClasses.length);
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 28 + MediaQuery.textScalerOf(context).scale(20),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => chips[i],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            state.paged
                ? '${state.filteredRows.length} 门（本地）'
                : '${state.visibleRows.length} 门 $classCount 班',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Page controls for the whole-school catalogue.
class _Pager extends StatelessWidget {
  const _Pager({required this.state, required this.onPage});
  final CoursesState state;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '上一页',
            onPressed: state.page > 0 ? () => onPage(state.page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('第 ${state.page + 1} / ${state.pageCount} 页',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          IconButton(
            tooltip: '下一页',
            onPressed: state.page + 1 < state.pageCount
                ? () => onPage(state.page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// A dropdown-style chip for a single-choice facet.
class _FacetMenu extends StatelessWidget {
  const _FacetMenu({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      tooltip: label,
      onSelected: (v) => onChanged(v == '' ? null : v),
      itemBuilder: (context) => [
        PopupMenuItem<String?>(value: '', child: Text('全部$label')),
        const PopupMenuDivider(),
        for (final o in options)
          PopupMenuItem<String?>(value: o, child: Text(o)),
      ],
      child: Chip(
        avatar: Icon(value == null ? Icons.filter_list : Icons.check, size: 16),
        label: Text(value ?? label),
        backgroundColor: value == null
            ? null
            : Theme.of(context).colorScheme.secondaryContainer,
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
          Text('${tc.courseName} ${tc.displayTitle}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
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
  const TextbookPicker({super.key, required this.options, this.title = '教材'});
  final List<TextbookOption> options;
  final String title;

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
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
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
                          if (book.author.isNotEmpty) book.author,
                          if (book.isbn.isNotEmpty) 'ISBN ${book.isbn}',
                          if (book.press.isNotEmpty) book.press,
                          if (book.price.isNotEmpty) '¥${book.price}',
                        ].join('  ')),
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
                            '不可订购',
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
              child: FilledButton(
                onPressed: _confirm,
                child: const Text('确定'),
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
