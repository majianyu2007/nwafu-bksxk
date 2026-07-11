/// A teaching-class row: capacity, conflict/test/book badges, and grab/monitor
/// actions. Used inside expandable course cards.
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
  });

  final TeachingClass teachingClass;
  final CourseKind kind;
  final VoidCallback onGrab;
  final VoidCallback onMonitor;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tc = teachingClass;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
      ),
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
                    Text(tc.displayTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (tc.teachingPlace.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(tc.teachingPlace,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              if (tc.isChoose)
                const StatusPill(label: '已选', color: Colors.green, icon: Icons.check),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.info_outline, size: 20, color: scheme.onSurfaceVariant),
                tooltip: '教学班详情',
                onPressed: () => showTeachingClassDetail(context, tc),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (tc.hasTest) const StatusPill(label: '含实验课', color: Colors.indigo, icon: Icons.science_outlined),
              if (tc.hasBook) const StatusPill(label: '需教材', color: Colors.brown, icon: Icons.menu_book_outlined),
              if (tc.isConflict) StatusPill(label: '冲突', color: Theme.of(context).colorScheme.error, icon: Icons.warning_amber),
            ],
          ),
          if (tc.isConflict && tc.conflictDesc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tc.conflictDesc, style: TextStyle(color: scheme.error, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CapacityBar(selected: tc.numberOfSelected, capacity: tc.classCapacity),
              ),
              const SizedBox(width: 12),
              _RefreshButton(onRefresh: onRefresh),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onMonitor,
                  icon: const Icon(Icons.radar, size: 18),
                  label: const Text('监控抢课'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: tc.isChoose ? null : onGrab,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text(tc.isChoose ? '已选' : (tc.isGrabbable ? '立即选' : '尝试选')),
                ),
              ),
            ],
          ),
        ],
      ),
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
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh, size: 18),
      tooltip: '刷新余量',
    );
  }
}
