/// Sheets of the timetable: course details (with colour picker, copy room,
/// 调课 notes) and the custom-course editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edu_providers.dart';
import '../../app/theme.dart';
import '../../app/ui_prefs.dart';
import '../../data/edu_models.dart';
import '../../data/timetable_logic.dart';
import '../../data/week_syntax.dart';
import '../widgets.dart';
import '../widgets/glass.dart';
import 'timetable_style.dart';

/// Title + close button + scrolling body, the content of every sheet here.
class TimetableSheet extends StatelessWidget {
  const TimetableSheet({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
  });
  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ...actions,
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

void showCourseDetails(
  BuildContext context,
  TermTimetable data,
  List<CourseSession> courses,
  int week,
) {
  showGlassSheet<void>(
    context,
    builder: (context) =>
        _CourseDetails(data: data, courses: courses, week: week),
  );
}

class _CourseDetails extends ConsumerWidget {
  const _CourseDetails({
    required this.data,
    required this.courses,
    required this.week,
  });
  final TermTimetable data;
  final List<CourseSession> courses;
  final int week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(courseColorsProvider);
    final theme = Theme.of(context);
    // This week's classes first; then the ones that use the same slot in
    // other weeks, under their own heading.
    final thisWeek = [
      for (final s in courses)
        if (s.runsInWeek(week)) s,
    ];
    final otherWeeks = [
      for (final s in courses)
        if (!s.runsInWeek(week)) s,
    ];
    final ordered = [...thisWeek, ...otherWeeks];
    final title = switch ((thisWeek.length, otherWeeks.length)) {
      (> 1, _) => '第 $week 周这里有 ${thisWeek.length} 门课',
      (1, _) => thisWeek.single.displayName,
      (_, 1) => otherWeeks.single.displayName,
      _ => '这个时间段的课',
    };
    return TimetableSheet(
      title: title,
      children: [
        if (thisWeek.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '时间冲突，请确认实际上哪一门',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        for (var i = 0; i < ordered.length; i++) ...[
          if (i == thisWeek.length &&
              otherWeeks.isNotEmpty &&
              ordered.length > 1) ...[
            if (i > 0) const SizedBox(height: 24),
            Text(
              thisWeek.isEmpty ? '第 $week 周这里没课，其他周的安排：' : '其他周这里还有：',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ] else if (i > 0)
            const Divider(height: 32),
          Builder(
            builder: (context) {
              final s = ordered[i];
              final color = colors.of(s);
              final notes = [
                for (final a in data.adjustments)
                  if (a.courseName.isNotEmpty &&
                      (s.displayName.contains(a.courseName) ||
                          a.courseName.contains(s.displayName)))
                    '${a.fromLabel} → ${a.toLabel}',
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.displayName,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusPill(
                        label: s.runsInWeek(week)
                            ? '第 $week 周有课'
                            : '非第 $week 周',
                        color: s.runsInWeek(week)
                            ? color
                            : theme.colorScheme.outline,
                      ),
                      if (s.custom)
                        StatusPill(
                          label: '自定义',
                          color: theme.colorScheme.tertiary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DetailRow(
                    '上课时间',
                    '${weekdayLabel(s.weekday)} ${timeLabel(data, s, on: data.dayOf(week, s.weekday))}',
                    icon: Icons.schedule,
                  ),
                  DetailRow(
                    '教学周',
                    s.weeksLabel.isNotEmpty
                        ? s.weeksLabel
                        : formatWeeks(s.weeks),
                    icon: Icons.date_range_outlined,
                  ),
                  if (s.room.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: DetailRow(
                            '教室',
                            s.room,
                            icon: Icons.place_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: '复制教室',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: s.room));
                            showToast(context, '已复制教室：${s.room}');
                          },
                        ),
                      ],
                    )
                  else
                    const DetailRow('教室', '未提供', icon: Icons.place_outlined),
                  DetailRow('教师', s.teacher, icon: Icons.person_outline),
                  DetailRow(
                    '学分',
                    s.credit == 0 ? '' : _num(s.credit),
                    icon: Icons.star_outline,
                  ),
                  DetailRow('校区', s.campus, icon: Icons.apartment_outlined),
                  DetailRow('课程号', s.courseCode, icon: Icons.tag),
                  DetailRow('课序号', s.classNo, icon: Icons.numbers),
                  DetailRow('课程性质', s.category, icon: Icons.category_outlined),
                  DetailRow('备注', s.note, icon: Icons.notes),
                  for (final n in notes)
                    DetailRow('调课', n, icon: Icons.swap_horiz),
                  DetailRow(
                    '来源',
                    s.custom ? '本地自定义课程' : '教务系统课表',
                    icon: Icons.cloud_outlined,
                  ),
                  const SizedBox(height: 12),
                  Text('课程颜色', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _ColorPicker(
                    selected: color,
                    custom: colors.isCustom(s),
                    onPick: (c) => ref
                        .read(uiPrefsProvider.notifier)
                        .setCourseColor(
                          colors.account,
                          courseKey(s),
                          c?.toARGB32(),
                        ),
                  ),
                  if (s.custom) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            showCustomCourseEditor(context, data, existing: s);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('删除自定义课程'),
                                content: Text('删除“${s.displayName}”？'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            await ref
                                .read(timetableProvider.notifier)
                                .removeCustom(s.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.selected,
    required this.custom,
    required this.onPick,
  });
  final Color selected;
  final bool custom;
  final ValueChanged<Color?> onPick;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final c in kCoursePalette)
        Semantics(
          button: true,
          selected: c.toARGB32() == selected.toARGB32(),
          label: '课程颜色',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onPick(c),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: c.toARGB32() == selected.toARGB32()
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 2.5,
                      )
                    : null,
              ),
              child: c.toARGB32() == selected.toARGB32()
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
        ),
      if (custom)
        TextButton(onPressed: () => onPick(null), child: const Text('恢复默认')),
    ],
  );
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// ---------------------------------------------------------------------------
// Custom course editor
// ---------------------------------------------------------------------------

/// Result of validating the editor's fields: a session to save, or the
/// per-field errors.
class CustomCourseDraft {
  const CustomCourseDraft({this.session, this.errors = const {}});
  final CourseSession? session;
  final Map<String, String> errors;
  bool get ok => session != null;
}

/// Pure validation, shared by the editor and its tests.
CustomCourseDraft validateCustomCourse({
  required String id,
  required String name,
  required String room,
  required String teacher,
  required int weekday,
  required int startPeriod,
  required int endPeriod,
  required String weeksText,
  int maxWeek = 30,
  int maxPeriod = 20,
}) {
  final errors = <String, String>{};
  if (name.trim().isEmpty) errors['name'] = '请输入课程名称';
  if (weekday < 1 || weekday > 7) errors['weekday'] = '请选择星期';
  if (startPeriod < 1 || startPeriod > maxPeriod) {
    errors['period'] = '开始节次无效';
  } else if (endPeriod < startPeriod || endPeriod > maxPeriod) {
    errors['period'] = '结束节次不能早于开始节次';
  }
  List<int>? weeks;
  try {
    weeks = parseWeeks(weeksText, maxWeek: maxWeek);
  } on FormatException catch (e) {
    errors['weeks'] = e.message;
  }
  if (errors.isNotEmpty) return CustomCourseDraft(errors: errors);
  return CustomCourseDraft(
    session: CourseSession(
      id: id,
      courseName: name.trim(),
      courseCode: '',
      classNo: '',
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weeks: weeks!,
      weeksLabel: formatWeeks(weeks),
      room: room.trim(),
      teacher: teacher.trim(),
      custom: true,
    ),
  );
}

/// Sessions in [data] (other than [self]) that share a weekday, period and
/// week with [s].
List<CourseSession> conflictsWith(
  TermTimetable data,
  CourseSession s, {
  String? self,
}) => [
  for (final o in data.sessions)
    if (o.id != self &&
        o.weekday == s.weekday &&
        o.startPeriod <= s.endPeriod &&
        s.startPeriod <= o.endPeriod &&
        o.weeks.any(s.weeks.contains))
      o,
];

Future<void> showCustomCourseEditor(
  BuildContext context,
  TermTimetable data, {
  CourseSession? existing,
  int? weekday,
}) => showGlassSheet<void>(
  context,
  builder: (context) =>
      CustomCourseEditor(data: data, existing: existing, weekday: weekday),
);

class CustomCourseEditor extends ConsumerStatefulWidget {
  const CustomCourseEditor({
    super.key,
    required this.data,
    this.existing,
    this.weekday,
  });
  final TermTimetable data;
  final CourseSession? existing;
  final int? weekday;

  @override
  ConsumerState<CustomCourseEditor> createState() => _CustomCourseEditorState();
}

class _CustomCourseEditorState extends ConsumerState<CustomCourseEditor> {
  late final _name = TextEditingController(text: widget.existing?.courseName);
  late final _room = TextEditingController(text: widget.existing?.room);
  late final _teacher = TextEditingController(text: widget.existing?.teacher);
  late final _weeks = TextEditingController(
    text: widget.existing == null
        ? '1-${widget.data.weekCount}周'
        : formatWeeks(widget.existing!.weeks),
  );
  late int _weekday = widget.existing?.weekday ?? widget.weekday ?? 1;
  late int _start = widget.existing?.startPeriod ?? 1;
  late int _end = widget.existing?.endPeriod ?? 2;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    _teacher.dispose();
    _weeks.dispose();
    super.dispose();
  }

  int get _maxPeriod {
    final p = periodIndices(widget.data);
    return p.isEmpty ? 12 : p.last.clamp(1, 20);
  }

  CustomCourseDraft _draft() => validateCustomCourse(
    id:
        widget.existing?.id ??
        'custom-${DateTime.now().microsecondsSinceEpoch}',
    name: _name.text,
    room: _room.text,
    teacher: _teacher.text,
    weekday: _weekday,
    startPeriod: _start,
    endPeriod: _end,
    weeksText: _weeks.text,
    maxWeek: widget.data.weekCount < 1 ? 30 : widget.data.weekCount,
    maxPeriod: _maxPeriod,
  );

  Future<void> _save() async {
    final draft = _draft();
    setState(() => _errors = draft.errors);
    if (!draft.ok) return;
    setState(() => _saving = true);
    await ref.read(timetableProvider.notifier).addCustom(draft.session!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft();
    final conflicts = draft.ok
        ? conflictsWith(widget.data, draft.session!, self: widget.existing?.id)
        : const <CourseSession>[];
    final previewWeeks = tryParseWeeks(_weeks.text, maxWeek: 60);
    final periods = [for (var p = 1; p <= _maxPeriod; p++) p];
    return TimetableSheet(
      title: widget.existing == null ? '添加课程' : '编辑课程',
      children: [
        TextField(
          controller: _name,
          autofocus: widget.existing == null,
          decoration: InputDecoration(
            labelText: '课程名称',
            errorText: _errors['name'],
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _room,
          decoration: const InputDecoration(labelText: '教室（可选）'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _teacher,
          decoration: const InputDecoration(labelText: '教师（可选）'),
        ),
        const SizedBox(height: 16),
        Text('星期', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var d = 1; d <= 7; d++)
              ChoiceChip(
                label: Text(weekdayLabel(d)),
                selected: _weekday == d,
                onSelected: (_) => setState(() => _weekday = d),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: const ValueKey('start-period'),
                initialValue: _start.clamp(1, _maxPeriod),
                decoration: const InputDecoration(labelText: '开始节次'),
                items: [
                  for (final p in periods)
                    DropdownMenuItem(value: p, child: Text('第 $p 节')),
                ],
                onChanged: (v) => setState(() {
                  _start = v ?? _start;
                  if (_end < _start) _end = _start;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('end-period-$_end'),
                initialValue: _end.clamp(1, _maxPeriod),
                decoration: InputDecoration(
                  labelText: '结束节次',
                  errorText: _errors['period'],
                ),
                items: [
                  for (final p in periods)
                    DropdownMenuItem(value: p, child: Text('第 $p 节')),
                ],
                onChanged: (v) => setState(() => _end = v ?? _end),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _weeks,
          decoration: InputDecoration(
            labelText: '周次',
            hintText: '如 1-16周、1-15周(单)、2,4,6周',
            errorText: _errors['weeks'],
            helperText: previewWeeks == null
                ? null
                : '共 ${previewWeeks.length} 周：${formatWeeks(previewWeeks)}',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          NoticeStrip(
            margin: EdgeInsets.zero,
            icon: Icons.warning_amber_outlined,
            text:
                '与 ${conflicts.map((c) => c.displayName).toSet().join('、')} '
                '时间重叠',
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('保存'),
        ),
        const SizedBox(height: 8),
        Text(
          '自定义课程只存在本机，同步课表不会覆盖。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
