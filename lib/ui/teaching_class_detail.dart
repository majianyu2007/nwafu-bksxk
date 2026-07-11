/// A bottom sheet showing full teaching-class detail: teacher, time/place,
/// capacity, exam, credit/hours, and any selection limits or conflict.
///
/// The site's own detail popup reads straight from the in-memory tcList row (no
/// extra request), so we do the same — everything here comes from the model we
/// already hold.
library;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'widgets.dart';

Future<void> showTeachingClassDetail(BuildContext context, TeachingClass tc, {DateTime? capacityAsOf}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _DetailSheet(tc: tc, capacityAsOf: capacityAsOf),
  );
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.tc, this.capacityAsOf});
  final TeachingClass tc;
  final DateTime? capacityAsOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(tc.courseName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tc.displayTitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
          const SizedBox(height: 16),

          // Conflict is the thing a user most needs to see before selecting.
          if (tc.isConflict)
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
                  Icon(Icons.warning_amber, color: scheme.onErrorContainer, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('时间冲突', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onErrorContainer)),
                        if (tc.conflictDesc.isNotEmpty)
                          Text(tc.conflictDesc, style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          _CapacityBlock(tc: tc, asOf: capacityAsOf),
          const SizedBox(height: 16),

          _row(context, Icons.person_outline, '教师', tc.teacherName),
          _row(context, Icons.schedule, '上课时间地点', tc.teachingPlace),
          if (tc.credit.isNotEmpty || tc.hours.isNotEmpty)
            _row(context, Icons.star_outline, '学分 / 学时',
                [if (tc.credit.isNotEmpty) '${tc.credit} 学分', if (tc.hours.isNotEmpty) '${tc.hours} 学时'].join(' · ')),
          if (tc.courseTypeName.isNotEmpty) _row(context, Icons.category_outlined, '课程类型', tc.courseTypeName),
          if (tc.teachingMethod.isNotEmpty) _row(context, Icons.cast_for_education, '授课方式', tc.teachingMethod),
          if (tc.examTime.isNotEmpty) _row(context, Icons.event_note, '考试时间', tc.examTime),
          if (tc.examType.isNotEmpty) _row(context, Icons.assignment_outlined, '考核方式', tc.examType),
          if (tc.hasTest) _row(context, Icons.science_outlined, '实验课', '需要选择实验教学班'),
          if (tc.hasBook) _row(context, Icons.menu_book_outlined, '教材', '需要教材征订'),
          if (tc.limits.isNotEmpty) _row(context, Icons.lock_outline, '选课限制', tc.limits.join('；')),
          _row(context, Icons.tag, '教学班号', tc.teachingClassId),
        ],
      ),
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
            child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
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
          CapacityBar(selected: tc.numberOfSelected, capacity: tc.classCapacity),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  asOf != null
                      ? '余量为 ${_fmt(asOf!)} 的快照，非实时。点击刷新获取最新。'
                      : '余量可能有延迟，非实时。',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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
