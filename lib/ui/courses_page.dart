/// Courses page: kind tabs, search, and expandable course cards with per-class
/// grab / monitor actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/constants.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';
import '../data/param_builders.dart';
import 'courses_controller.dart';
import 'teaching_class_tile.dart';
import 'widgets.dart';

/// Sentinel returned in [book] field when user cancels textbook selection.
const _kBookCancelled = '__CANCEL_TEXTBOOK__';

class CoursesPage extends ConsumerStatefulWidget {
  const CoursesPage({super.key});

  @override
  ConsumerState<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends ConsumerState<CoursesPage> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coursesProvider);
    final ctrl = ref.read(coursesProvider.notifier);

    return Column(
      children: [
        _Header(
          kind: state.kind,
          onKind: ctrl.setKind,
          searchCtrl: _searchCtrl,
          onSearch: (q) {
            ctrl.setQuery(q);
            ctrl.load();
          },
        ),
        Expanded(child: _body(context, state, ctrl)),
      ],
    );
  }

  Widget _body(BuildContext context, CoursesState state, CoursesController ctrl) {
    if (state.loading && state.rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.rows.isEmpty) {
      return _ErrorState(message: state.error!, onRetry: ctrl.load);
    }
    if (!state.loadedOnce) {
      return EmptyState(
        icon: Icons.touch_app_outlined,
        title: '选择课程类型开始',
        subtitle: '点击上方标签加载「${state.kind.label}」，或输入关键字搜索。',
      );
    }
    if (state.rows.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '没有找到课程',
        subtitle: '换一个课程类型或关键字试试。当前轮次可能未开放该类别。',
      );
    }
    return RefreshIndicator(
      onRefresh: ctrl.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: state.rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _CourseCard(row: state.rows[i], kind: state.kind),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.kind,
    required this.onKind,
    required this.searchCtrl,
    required this.onSearch,
  });

  final CourseKind kind;
  final ValueChanged<CourseKind> onKind;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text('选课', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索课程名 / 课程号',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => onSearch(searchCtrl.text.trim()),
                ),
              ),
              onSubmitted: (q) => onSearch(q.trim()),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final k in CourseKind.values)
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
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
        ],
      ),
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

class _CourseCardState extends ConsumerState<_CourseCard> {
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
            onTap: classes.isEmpty ? null : () => setState(() => _expanded = !_expanded),
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
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                            if (row.selected) ...[
                              const SizedBox(width: 8),
                              const StatusPill(label: '已选', color: Colors.green, icon: Icons.check),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            row.courseNumber,
                            if (row.credit.isNotEmpty) '${row.credit}学分',
                            if (row.courseNatureName.isNotEmpty) row.courseNatureName,
                            if (row.departmentName.isNotEmpty) row.departmentName,
                          ].join(' · '),
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (classes.isNotEmpty)
                    Row(
                      children: [
                        Text('${classes.length}个班',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: scheme.onSurfaceVariant),
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
                onGrab: () => _grab(tc),
                onMonitor: () => _monitor(tc),
                onRefresh: () => ref.read(coursesProvider.notifier).refresh(tc),
              ),
        ],
      ),
    );
  }

  Future<void> _grab(TeachingClass tc) async {
    final ctrl = ref.read(coursesProvider.notifier);
    // Immediate conflict feedback: tell the user before we submit, using the
    // conflict flag the server already put on this row.
    if (tc.isConflict) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('课程时间冲突'),
          content: Text(tc.conflictDesc.isNotEmpty
              ? '该教学班与已选课程冲突：\n${tc.conflictDesc}\n\n仍要尝试选课吗？'
              : '该教学班与已选课程存在时间冲突。仍要尝试选课吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('仍要选')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      final (testId, book) = await _resolveSelectionsIfNeeded(tc);
      if (book == _kBookCancelled) return; // toast already shown by prompt
      final outcome = await ctrl.grabNow(tc, testTeachingClassId: testId, bookSelection: book);
      if (!mounted) return;
      showToast(context, outcome.message, success: outcome.success);
    } on MissingSelectionError catch (e) {
      if (!mounted) return;
      showToast(context, e.reason, success: false);
    } catch (e) {
      if (!mounted) return;
      showToast(context, '$e', success: false);
    }
  }

  Future<void> _monitor(TeachingClass tc) async {
    final ctrl = ref.read(coursesProvider.notifier);
    try {
      final (testId, book) = await _resolveSelectionsIfNeeded(tc);
      if (book == _kBookCancelled) return; // toast already shown by prompt
      final watch = ctrl.addToMonitor(tc, testTeachingClassId: testId, bookSelection: book);
      if (!mounted) return;
      final needsSetup = watch.status == WatchStatus.needsSetup;
      showToast(
        context,
        needsSetup ? '已加入监控，但仍需完成实验课/教材选择' : '已加入监控：${tc.courseName}',
        success: !needsSetup,
      );
    } catch (e) {
      if (!mounted) return;
      showToast(context, '$e', success: false);
    }
  }

  /// If the class needs a test class or textbook, prompt for them; otherwise
  /// return nulls. Returns (testTeachingClassId, bookSelection).
  Future<(String?, String?)> _resolveSelectionsIfNeeded(TeachingClass tc) async {
    String? testId;
    String? book;
    if (tc.hasTest && tc.testTeachingClassId.isEmpty) {
      testId = await _pickTestClass(tc);
    } else if (tc.hasTest) {
      testId = tc.testTeachingClassId;
    }
    if (tc.hasBook) {
      final sel = await _promptTextbookSelection(tc);
      if (sel == null) return (testId, _kBookCancelled);
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
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => _TestClassPicker(list: list),
    );
  }

  Future<TextbookSelection?> _promptTextbookSelection(TeachingClass tc) async {
    final session = ref.read(sessionProvider);
    final student = session.student;
    final batch = session.activeBatch;
    if (student == null || batch == null) return null;

    // Show loading indicator.
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
      final options = await ref.read(courseServiceProvider).fetchTextbookOptions(
        studentCode: student.studentCode,
        batchCode: batch.code,
        teachingClassId: tc.teachingClassId,
      );

      if (!mounted) return null;
      Navigator.of(context).pop(); // dismiss loading

      if (options.isEmpty) {
        showToast(context, '未获取到教材清单，按默认提交');
        final book = tc.needBook.isNotEmpty ? tc.needBook : '';
        return TextbookSelection(book, []);
      }

      final sel = await showModalBottomSheet<TextbookSelection>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => _TextbookPicker(options: options),
      );
      if (sel == null) {
        if (!mounted) return null;
        showToast(context, '已取消教材选择', success: false);
      }
      return sel;
    } catch (e) {
      if (!mounted) return null;
      Navigator.of(context).pop(); // dismiss loading on error
      showToast(context, '获取教材信息失败', success: false);
      return null;
    }
  }
}

class _TestClassPicker extends StatelessWidget {
  const _TestClassPicker({required this.list});
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
              title: Text('${item['courseName'] ?? item['teachingClassName'] ?? '实验班'}'),
              subtitle: Text('${item['teacherName'] ?? ''}  ${item['teachingPlace'] ?? ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(
                '${item['testTeachingClassID'] ?? item['teachingClassID'] ?? item['teachingClassId'] ?? ''}',
              ),
            ),
        ],
      ),
    );
  }
}

class _TextbookPicker extends StatefulWidget {
  const _TextbookPicker({required this.options});
  final List<TextbookOption> options;

  @override
  State<_TextbookPicker> createState() => _TextbookPickerState();
}

class _TextbookPickerState extends State<_TextbookPicker> {
  late List<bool> _ordered;
  late List<String> _reasonCodes;

  @override
  void initState() {
    super.initState();
    _ordered = List.generate(
      widget.options.length,
      (i) => widget.options[i].orderable,
    );
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
          // mainAxisSize.min → default (max) so Column fills available height
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
                          '\u00a5${book.price}',
                        ].join(' \u00b7 ')),
                        value: _ordered[i],
                        enabled: book.orderable,
                        onChanged: book.orderable
                            ? (v) => setState(() {
                                  _ordered[i] = v ?? true;
                                  if (!_ordered[i] &&
                                      _reasonCodes[i].isEmpty &&
                                      book.reasonCodes.isNotEmpty) {
                                    _reasonCodes[i] = book.reasonCodes.first.code;
                                  }
                                })
                            : null,
                      ),
                      if (!_ordered[i] && book.reasonCodes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                          child: DropdownButtonFormField<String>(
                            initialValue: _reasonCodes[i].isNotEmpty ? _reasonCodes[i] : null,
                            decoration: const InputDecoration(
                              labelText: '\u4e0d\u8ba2\u8d2d\u539f\u56e0',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              isDense: true,
                            ),
                            items: book.reasonCodes
                                .map((r) => DropdownMenuItem(value: r.code, child: Text(r.name)))
                                .toList(),
                            onChanged: (v) => setState(() => _reasonCodes[i] = v ?? ''),
                          ),
                        ),
                      if (!book.orderable)
                        Padding(
                          padding: const EdgeInsets.only(left: 72, bottom: 8),
                          child: Text('\u8be5\u6559\u6750\u4e0d\u53ef\u8ba2\u8d2d',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
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
                label: const Text('\u786e\u8ba4\u6559\u6750\u9009\u62e9'),
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
            Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
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
