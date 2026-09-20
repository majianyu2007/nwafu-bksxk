/// A teaching-class row: title, place, badges, capacity and the grab /
/// monitor actions. Used inside course cards and the wide detail pane.
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'teaching_class_detail.dart';
import 'widgets.dart';

class TeachingClassTile extends StatelessWidget {
  const TeachingClassTile({
    super.key,
    required this.teachingClass,
    required this.kind,
    required this.onGrab,
    required this.onMonitor,
    required this.onRefresh,
    this.watched = false,
    this.busy = false,
    this.bordered = true,
    this.browseOnly = false,
    this.volunteerRound = false,
    this.courseAlreadyHeld = false,
    this.onCheck,
  });

  final TeachingClass teachingClass;
  final CourseKind kind;
  final VoidCallback onGrab;

  /// Adds the class to the monitor, or removes it when [watched].
  final VoidCallback onMonitor;
  final Future<void> Function() onRefresh;

  /// The class is already on this account's watch list.
  final bool watched;
  final bool busy;

  /// Draw the top separator used when tiles stack inside a course card. Off
  /// when the tile is the sole child of its own card (wide detail pane).
  final bool bordered;

  /// Whole-school query rows: the official page only lets you look these up
  /// and run the 检查 (canchoose) query; selection happens under the class's
  /// own category, and the rows carry no capacity.
  final bool browseOnly;

  /// 预选 round: capacity is expressed as first-choice volunteers vs seats and
  /// the primary action files a volunteer grade instead of grabbing a seat.
  final bool volunteerRound;

  /// The student already holds another class of this course; the server
  /// refuses a second class of the same course.
  final bool courseAlreadyHeld;

  /// Opens the server's 能否选课 check (browse-only rows).
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tc = teachingClass;
    final platform = tc.onlinePlatform;

    return Container(
      decoration: bordered
          ? BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.4))),
            )
          : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tc.displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      tc.teachingPlace.isNotEmpty
                          ? tc.teachingPlace
                          : platform.isNotEmpty
                              ? '$platform 网课，无固定上课时间'
                              : '上课时间地点未安排',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (tc.isHeld)
                StatusPill(
                    label: volunteerRound && tc.heldVolunteerGrade.isNotEmpty
                        ? '第${tc.heldVolunteerGrade}志愿'
                        : '已选',
                    color: Colors.green,
                    icon: Icons.check),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.info_outline,
                    size: 20, color: scheme.onSurfaceVariant),
                tooltip: '详情',
                onPressed: () => showTeachingClassDetail(context, tc),
              ),
            ],
          ),
          if (platform.isNotEmpty ||
              tc.hasTest ||
              tc.hasBook ||
              tc.isConflict ||
              watched) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (platform.isNotEmpty)
                  StatusPill(
                      label: platform,
                      color: Colors.teal,
                      icon: Icons.laptop_outlined),
                if (tc.hasTest)
                  const StatusPill(
                      label: '含实验课',
                      color: Colors.indigo,
                      icon: Icons.science_outlined),
                if (tc.hasBook)
                  const StatusPill(
                      label: '需教材',
                      color: Colors.brown,
                      icon: Icons.menu_book_outlined),
                if (tc.isConflict)
                  StatusPill(
                      label: '时间冲突',
                      color: scheme.error,
                      icon: Icons.warning_amber),
                if (watched)
                  StatusPill(
                      label: '监控中', color: scheme.primary, icon: Icons.radar),
              ],
            ),
          ],
          if (tc.isConflict && tc.conflictDesc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tc.conflictDesc,
                style: TextStyle(color: scheme.error, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CapacityBar(
                  selected:
                      volunteerRound ? tc.firstVolunteers : tc.numberOfSelected,
                  capacity: tc.classCapacity,
                  known: tc.hasCapacityInfo,
                  label: volunteerRound ? '第一志愿' : null,
                ),
              ),
              if (!browseOnly) ...[
                const SizedBox(width: 12),
                _RefreshButton(onRefresh: onRefresh),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _actions(context),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tc = teachingClass;
    const spinner = SizedBox(
        height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2));

    if (browseOnly) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '全校课程只能查询，请到所属类别选课',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          if (onCheck != null)
            OutlinedButton.icon(
              onPressed: onCheck,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('检查能否选'),
            ),
        ],
      );
    }
    if (tc.isHeld) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.check, size: 18),
          label: Text(volunteerRound ? '已填报' : '已选'),
        ),
      );
    }
    if (courseAlreadyHeld) {
      return Text(
        '已选了本课程的另一个教学班，换班请先退选',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }
    final monitorButton = Expanded(
      child: watched
          ? FilledButton.tonalIcon(
              onPressed: busy ? null : onMonitor,
              icon: const Icon(Icons.radar, size: 18),
              label: const Text('取消监控'),
            )
          : OutlinedButton.icon(
              onPressed: busy ? null : onMonitor,
              icon: const Icon(Icons.radar, size: 18),
              label: const Text('加入监控'),
            ),
    );
    if (volunteerRound) {
      // 预选: there is no seat race; filing a volunteer is the action.
      return Row(
        children: [
          monitorButton,
          const SizedBox(width: 10),
          Expanded(
            child: tc.isConflict
                ? FilledButton.tonalIcon(
                    onPressed: busy ? null : onGrab,
                    icon: busy ? spinner : const Icon(Icons.warning_amber, size: 18),
                    label: const Text('有冲突，仍填报'),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : onGrab,
                    icon: busy
                        ? spinner
                        : const Icon(Icons.how_to_vote_outlined, size: 18),
                    label: const Text('填报志愿'),
                  ),
          ),
        ],
      );
    }
    if (tc.remaining > 0) {
      return Row(
        children: [
          monitorButton,
          const SizedBox(width: 10),
          Expanded(
            child: tc.isConflict
                ? FilledButton.tonalIcon(
                    onPressed: busy ? null : onGrab,
                    icon: busy ? spinner : const Icon(Icons.warning_amber, size: 18),
                    label: const Text('有冲突，仍要选'),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : onGrab,
                    icon: busy ? spinner : const Icon(Icons.bolt, size: 18),
                    label: const Text('选课'),
                  ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: TextButton.icon(
            onPressed: busy ? null : onGrab,
            icon: const Icon(Icons.send_outlined, size: 17),
            label: const Text('仍要提交'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: watched
              ? FilledButton.tonalIcon(
                  onPressed: busy ? null : onMonitor,
                  icon: const Icon(Icons.radar, size: 18),
                  label: const Text('取消监控'),
                )
              : FilledButton.icon(
                  onPressed: busy ? null : onMonitor,
                  icon: busy ? spinner : const Icon(Icons.radar, size: 18),
                  label: const Text('已满，监控空位'),
                ),
        ),
      ],
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.onRefresh});
  final Future<void> Function() onRefresh;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onRefresh();
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh, size: 18),
      tooltip: '刷新余量',
    );
  }
}
