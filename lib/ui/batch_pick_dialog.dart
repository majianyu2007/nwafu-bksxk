/// Post-login batch picker: mirrors the official site's flow of consciously
/// choosing a selection round before entering the grabbing UI, and surfaces the
/// student's 已修/还需 credits so they can plan.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/models.dart';
import 'widgets.dart';

/// Shows the batch-pick dialog. If [batches] is omitted, reads them from the
/// active session. Sets the chosen batch on the session and toasts the result.
Future<void> showBatchPickDialog(BuildContext context, WidgetRef ref, {List<ElectiveBatch>? batches}) async {
  final session = ref.read(sessionProvider);
  final list = batches ?? session.batches;
  final hasOpen = list.any((b) => b.canSelect);

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _BatchPickDialog(
      batches: list,
      title: hasOpen ? '请选择选课轮次' : '当前没有可选的轮次',
      subtitle: hasOpen
          ? '选择一个轮次后即可进入选课。未开放的轮次稍后在首页刷新可重选。'
          : '当前所有可见轮次均未开放，稍后请在首页右上角刷新查看。可以先关闭此提示，待开放后再选择。',
      canPick: hasOpen,
      onPick: (b) {
        ref.read(sessionProvider.notifier).setActiveBatch(b);
        Navigator.of(dialogContext).pop();
        showToast(context, '已选择轮次：${b.name.isEmpty ? b.code : b.name}', success: true);
      },
      onSkip: () => Navigator.of(dialogContext).pop(),
    ),
  );
}

class _BatchPickDialog extends ConsumerStatefulWidget {
  const _BatchPickDialog({
    required this.batches,
    required this.title,
    required this.subtitle,
    required this.canPick,
    required this.onPick,
    required this.onSkip,
  });

  final List<ElectiveBatch> batches;
  final String title;
  final String subtitle;
  final bool canPick;
  final ValueChanged<ElectiveBatch> onPick;
  final VoidCallback onSkip;

  @override
  ConsumerState<_BatchPickDialog> createState() => _BatchPickDialogState();
}

class _BatchPickDialogState extends ConsumerState<_BatchPickDialog> {
  CreditInfo? _credit;
  bool _creditLoading = false;
  String? _selectedCode;

  @override
  void initState() {
    super.initState();
    final open = widget.batches.where((b) => b.canSelect).toList();
    if (open.isNotEmpty) _selectedCode = open.first.code;
    _loadCredit();
  }

  Future<void> _loadCredit() async {
    final session = ref.read(sessionProvider);
    final st = session.student;
    if (st == null) return;
    final target = widget.batches.firstWhere(
      (b) => b.code == _selectedCode,
      orElse: () => widget.batches.isNotEmpty ? widget.batches.first : ElectiveBatch(code: '', name: '', batchType: '', canSelect: false),
    );
    if (target.code.isEmpty) return;
    setState(() => _creditLoading = true);
    try {
      final c = await ref.read(infoServiceProvider).fetchCreditInfo(
            studentCode: st.studentCode,
            electiveBatchCode: target.code,
            batchType: target.batchType,
          );
      if (mounted) setState(() => _credit = c);
    } catch (_) {
      // non-fatal
    } finally {
      if (mounted) setState(() => _creditLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 14),
              // credit summary for the highlighted/selected batch
              _CreditSummary(credit: _credit, loading: _creditLoading),
              const SizedBox(height: 14),
              RadioGroup<String>(
                groupValue: _selectedCode,
                onChanged: (v) {
                  if (!widget.canPick || v == null) return;
                  setState(() => _selectedCode = v);
                  _loadCredit();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final b in widget.batches)
                      RadioListTile<String>(
                        value: b.code,
                        enabled: widget.canPick && b.canSelect,
                        title: Text(b.name.isEmpty ? b.code : b.name),
                        subtitle: b.beginTime.isNotEmpty
                            ? Text('${b.beginTime}  →  ${b.endTime}', style: const TextStyle(fontSize: 12))
                            : null,
                        secondary: StatusPill(
                          label: b.canSelect ? '开放' : '未开放',
                          color: b.canSelect ? Colors.green : scheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onSkip, child: const Text('稍后再说')),
        if (widget.canPick)
          FilledButton(
            onPressed: _selectedCode == null
                ? null
                : () {
                    final b = widget.batches.firstWhere((e) => e.code == _selectedCode);
                    widget.onPick(b);
                  },
            child: const Text('确认选择'),
          ),
      ],
    );
  }
}

class _CreditSummary extends StatelessWidget {
  const _CreditSummary({required this.credit, required this.loading});
  final CreditInfo? credit;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      return const Row(children: [
        SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8),
        Text('加载学分信息…', style: TextStyle(fontSize: 13)),
      ]);
    }
    final c = credit;
    if (c == null || c.raw.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text('选课学分', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _Stat('已修', c.getCredit.toStringAsFixed(c.getCredit == c.getCredit.roundToDouble() ? 0 : 1)),
              const SizedBox(width: 16),
              _Stat('需修', c.needCredit.toStringAsFixed(c.needCredit == c.needCredit.roundToDouble() ? 0 : 1)),
              const SizedBox(width: 16),
              _Stat(
                '还需',
                c.remainingCredit.toStringAsFixed(c.remainingCredit == c.remainingCredit.roundToDouble() ? 0 : 1),
                highlight: true,
              ),
            ],
          ),
          if (c.noSelectReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(c.noSelectReason, style: TextStyle(color: scheme.error, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: highlight ? scheme.primary : null)),
      ],
    );
  }
}