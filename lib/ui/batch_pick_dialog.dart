/// Post-login batch picker: mirrors the official site's flow of consciously
/// choosing a selection round before entering the grabbing UI, and surfaces the
/// student's 总/已获/已选 credits so they can plan.
library;

import 'dart:math' as math;
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
      title: hasOpen ? '选择轮次' : '没有开放的轮次',
      subtitle: hasOpen ? '' : '开放后在首页刷新即可选择。',
      canPick: hasOpen,
      onPick: (b) {
        ref.read(currentSessionControllerProvider).setActiveBatch(b);
        Navigator.of(dialogContext).pop();
        showToast(context, '已选择 ${b.name.isEmpty ? b.code : b.name}', success: true);
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = math.min(600.0, math.max(300.0, viewportWidth - 64));
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      title: Row(
        children: [
          Icon(Icons.event_available_outlined, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: contentWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.subtitle.isNotEmpty) ...[
                Text(widget.subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              _CreditSummary(credit: _credit, loading: _creditLoading),
              const SizedBox(height: 10),
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: RadioListTile<String>(
                          value: b.code,
                          enabled: widget.canPick && b.canSelect,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          title: Text(
                            b.name.isEmpty ? b.code : b.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            [
                              if (b.beginTime.isNotEmpty) '${b.beginTime} 至 ${b.endTime}',
                              [
                                if (b.typeName.isNotEmpty) b.typeName,
                                if (b.tacticName.isNotEmpty) b.tacticName,
                              ].join('  '),
                              if (!b.canSelect && b.noSelectReason.isNotEmpty) b.noSelectReason,
                            ].where((e) => e.isNotEmpty).join('\n'),
                            style: const TextStyle(fontSize: 11),
                          ),
                          secondary: StatusPill(
                            label: b.canSelect ? '开放' : '未开放',
                            color: b.canSelect ? Colors.green : scheme.error,
                          ),
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
        TextButton(onPressed: widget.onSkip, child: const Text('稍后')),
        if (widget.canPick)
          FilledButton.icon(
            onPressed: _selectedCode == null
                ? null
                : () {
                    final b = widget.batches.firstWhere((e) => e.code == _selectedCode);
                    widget.onPick(b);
                  },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('确定'),
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
      return const SizedBox(
        height: 58,
        child: Row(children: [
          SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('加载学分信息…', style: TextStyle(fontSize: 13)),
        ]),
      );
    }
    final c = credit;
    if (c == null || c.raw.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '选课学分',
                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _Stat('总学分', _creditText(c.totalCredit))),
              _CreditDivider(color: scheme.outlineVariant),
              Expanded(child: _Stat('已获', _creditText(c.getCredit))),
              _CreditDivider(color: scheme.outlineVariant),
              Expanded(child: _Stat('已选', _creditText(c.selectedCredit), highlight: true)),
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

  static String _creditText(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
}

class _CreditDivider extends StatelessWidget {
  const _CreditDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: color,
      );
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