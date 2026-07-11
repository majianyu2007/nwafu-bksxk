/// Selected-courses page: the student's current enrollments with drop actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/models.dart';
import 'widgets.dart';

/// Loads selected courses for the active session.
final selectedCoursesProvider = FutureProvider.autoDispose<List<TeachingClass>>((ref) async {
  final session = ref.watch(sessionProvider);
  final student = session.student;
  final batch = session.activeBatch;
  if (student == null || batch == null) return [];
  final course = ref.read(courseServiceProvider);
  return course.fetchSelected(studentCode: student.studentCode, batchCode: batch.code);
});

class SelectedPage extends ConsumerWidget {
  const SelectedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(selectedCoursesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('已选课程', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                onPressed: () => ref.invalidate(selectedCoursesProvider),
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(
              icon: Icons.cloud_off,
              title: '加载失败',
              subtitle: '$e',
            ),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.checklist,
                  title: '还没有已选课程',
                  subtitle: '在「选课」页选课后会显示在这里。',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(selectedCoursesProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _SelectedCard(tc: list[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SelectedCard extends ConsumerStatefulWidget {
  const _SelectedCard({required this.tc});
  final TeachingClass tc;

  @override
  ConsumerState<_SelectedCard> createState() => _SelectedCardState();
}

class _SelectedCardState extends ConsumerState<_SelectedCard> {
  bool _dropping = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tc = widget.tc;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tc.courseName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(tc.displayTitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            if (tc.teachingPlace.isNotEmpty)
              Text(tc.teachingPlace, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              children: [
                const StatusPill(label: '已选', color: Colors.green, icon: Icons.check),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _dropping ? null : _confirmDrop,
                  icon: _dropping
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.remove_circle_outline, size: 18, color: scheme.error),
                  label: Text('退选', style: TextStyle(color: scheme.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDrop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退选'),
        content: Text('确定要退选「${widget.tc.courseName}」吗？此操作会真实改变你的选课状态。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认退选')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _dropping = true);
    try {
      final session = ref.read(sessionProvider);
      final enroll = ref.read(enrollServiceProvider);
      final outcome = await enroll.dropCourse(
        teachingClassId: widget.tc.teachingClassId,
        studentCode: session.student!.studentCode,
        batchCode: session.activeBatch!.code,
      );
      if (!mounted) return;
      showToast(context, outcome.message, success: outcome.success);
      if (outcome.success) ref.invalidate(selectedCoursesProvider);
    } catch (e) {
      if (!mounted) return;
      showToast(context, '$e', success: false);
    } finally {
      if (mounted) setState(() => _dropping = false);
    }
  }
}
