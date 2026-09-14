/// A bottom sheet showing full teaching-class detail: teacher, time/place,
/// capacity, exam, credit/hours, and any selection limits or conflict.
///
/// Starts from the in-memory tcList row. When an active elective batch is
/// available the sheet performs a live lookup from the school server to
/// enrich fields (teacher info, course introduction, course nature,
/// department name) without downgrading any locally-held data. Falls back
/// silently to the local data on any error.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/models.dart';
import 'layout.dart';
import 'widgets.dart';

Future<void> showTeachingClassDetail(BuildContext context, TeachingClass tc,
    {DateTime? capacityAsOf}) {
  final dialog = adaptiveSheetIsDialog(context);
  return showAdaptiveSheet<void>(
    context,
    scrollControlled: true,
    maxWidth: 680,
    builder: (context) =>
        _DetailSheet(tc: tc, capacityAsOf: capacityAsOf, inDialog: dialog),
  );
}

class _DetailSheet extends ConsumerStatefulWidget {
  const _DetailSheet(
      {required this.tc, this.capacityAsOf, this.inDialog = false});
  final TeachingClass tc;
  final DateTime? capacityAsOf;

  /// Presented as a dialog (wide windows): render a plain list instead of a
  /// draggable sheet, which only makes sense anchored to the screen bottom.
  final bool inDialog;

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  late TeachingClass _tc;
  Map<String, dynamic>? _courseDetail;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tc = widget.tc;
    _tryFetchDetail();
  }

  void _tryFetchDetail() {
    final batchCode = ref.read(sessionProvider).activeBatch?.code;
    if (batchCode == null || batchCode.isEmpty) return;

    _loading = true;
    Future(() async {
      try {
        final course = ref.read(courseServiceProvider);

        final fresh = await course.fetchTeachingClassDetail(
            tc: widget.tc, batchCode: batchCode);
        if (fresh != null && mounted) {
          setState(() => _tc = fresh);
        }

        if (widget.tc.courseNumber.isNotEmpty && mounted) {
          final detail = await course.fetchCourseDetail(widget.tc.courseNumber);
          if (mounted) {
            setState(() => _courseDetail = detail);
          }
        }
      } catch (_) {
        // Ignore — fall back to local data.
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Derived data
  // ---------------------------------------------------------------------------

  String get _courseNatureName {
    final d = _courseDetail?['courseNatureName'];
    if (d is String && d.isNotEmpty) return d;
    return _s(_tc.raw['courseNatureName']);
  }

  String get _departmentName {
    final d = _courseDetail?['departmentName'];
    if (d is String && d.isNotEmpty) return d;
    return _s(_tc.raw['departmentName']);
  }

  static String _s(dynamic v) => v == null ? '' : v.toString().trim();

  /// A field from the querykcxx.do payload, or ''.
  String _kcxx(String key) => _s(_courseDetail?[key]);

  /// querykcxx.do gives the exam type as text (上机考试); queryjxb.do only a
  /// code ("2"), which is not worth showing on its own.
  String get _examTypeLabel {
    final text = _kcxx('examtype');
    if (text.isNotEmpty) return text;
    final code = _tc.examType;
    return int.tryParse(code) == null ? code : '';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.inDialog) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: _content(context),
      );
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: _content(context),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Text(_tc.courseName,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(_tc.displayTitle,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
      const SizedBox(height: 16),

      // Conflict is the thing a user most needs to see before selecting.
      if (_tc.isConflict)
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber,
                  color: scheme.onErrorContainer, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('时间冲突',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: scheme.onErrorContainer)),
                    if (_tc.conflictDesc.isNotEmpty)
                      Text(_tc.conflictDesc,
                          style: TextStyle(
                              color: scheme.onErrorContainer, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),

      _CapacityBlock(tc: _tc, asOf: widget.capacityAsOf),
      const SizedBox(height: 16),

      _row(context, Icons.person_outline, '教师', _tc.teacherName),
      _teacherExtra(),

      _row(context, Icons.schedule, '上课时间地点', _tc.teachingPlace),

      if (_tc.credit.isNotEmpty || _tc.hours.isNotEmpty)
        _row(
          context,
          Icons.star_outline,
          '学分 / 学时',
          [
            if (_tc.credit.isNotEmpty) '${_tc.credit} 学分',
            if (_tc.hours.isNotEmpty) '${_tc.hours} 学时',
          ].join(' · '),
        ),

      if (_tc.courseTypeName.isNotEmpty)
        _row(context, Icons.category_outlined, '课程类型', _tc.courseTypeName),

      if (_courseNatureName.isNotEmpty &&
          _courseNatureName != _tc.courseTypeName)
        _row(context, Icons.account_tree_outlined, '课程性质', _courseNatureName),

      if (_departmentName.isNotEmpty)
        _row(context, Icons.business_outlined, '开课院系', _departmentName),

      if (_tc.teachingMethod.isNotEmpty)
        _row(context, Icons.cast_for_education, '授课方式', _tc.teachingMethod),
      if (_tc.examTime.isNotEmpty)
        _row(context, Icons.event_note, '考试时间', _tc.examTime),
      if (_examTypeLabel.isNotEmpty)
        _row(context, Icons.assignment_outlined, '考核方式', _examTypeLabel),
      if (_kcxx('englishCourseName').isNotEmpty)
        _row(context, Icons.translate, '英文名', _kcxx('englishCourseName')),
      if (_kcxx('courselanguage').isNotEmpty)
        _row(context, Icons.language, '授课语言', _kcxx('courselanguage')),
      if (_kcxx('courselevel').isNotEmpty)
        _row(context, Icons.stairs_outlined, '课程层次', _kcxx('courselevel')),
      if (_tc.recommendSchoolClass.isNotEmpty)
        _row(context, Icons.groups_outlined, '推荐班级', _tc.recommendSchoolClass),

      _introBlock(),

      if (_tc.hasTest)
        _row(context, Icons.science_outlined, '实验课', '需要选择实验教学班'),
      if (_tc.hasBook) _row(context, Icons.menu_book_outlined, '教材', '需要教材征订'),
      if (_tc.limits.isNotEmpty)
        _row(context, Icons.lock_outline, '选课限制', _tc.limits.join('；')),
      _row(context, Icons.tag, '教学班号', _tc.teachingClassId),
    ];
  }

  /// Optional second row under the teacher name with title / department from the
  /// live course detail. Shows a tiny spinner while the detail is loading.
  Widget _teacherExtra() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(left: 30, bottom: 8),
        child: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    final parts = <String>[];
    // queryjxb.do's teacherNameList carries the title: "武春芳(副教授)|工号|".
    final withTitle = _tc.teacherWithTitle;
    if (withTitle.isNotEmpty && withTitle != _tc.teacherName) {
      parts.add(withTitle);
    }
    if (_departmentName.isNotEmpty) parts.add(_departmentName);
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 30, bottom: 8),
      child: Text(
        parts.join(' · '),
        style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  /// Course introduction block sourced from the live course-detail map.
  /// Strips HTML tags if present. Shows a tiny spinner while loading.
  Widget _introBlock() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text('加载课程简介…',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    final rawIntro = _courseDetail?['introduction'] ??
        _courseDetail?['coursesummary'] ??
        _courseDetail?['courseoutline'] ??
        _courseDetail?['content'] ??
        _courseDetail?['description'];
    if (rawIntro == null) return const SizedBox.shrink();
    var text = rawIntro.toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    // Strip HTML tags when the server returns rich text.
    if (text.contains('<')) {
      text = text.replaceAll(RegExp(r'<[^>]*>'), '');
      text = text.trim();
    }
    if (text.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          '课程简介',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

class _CapacityBlock extends StatelessWidget {
  const _CapacityBlock({required this.tc, this.asOf});
  final TeachingClass tc;
  final DateTime? asOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CapacityBar(
              selected: tc.numberOfSelected, capacity: tc.classCapacity),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  asOf != null
                      ? '余量为 ${_fmt(asOf!)} 的快照，非实时。点击刷新获取最新。'
                      : '余量可能有延迟，非实时。',
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
