/// Interactive What-If GPA calculator & Target GPA reverse planner: add
/// hypothetical courses, exclude existing courses, or calculate the minimum
/// average GPA needed over upcoming credits to reach a target GPA.
library;

import 'package:flutter/material.dart';

import '../data/edu_models.dart';
import '../data/gpa_simulator.dart';
import 'grades_trend.dart';
import 'widgets.dart';
import 'widgets/glass.dart';

class GpaSimulatorSheet extends StatefulWidget {
  const GpaSimulatorSheet({
    super.key,
    required this.records,
    this.hidden = false,
    this.currentTermCredits = 20,
  });
  final List<GradeRecord> records;
  final bool hidden;
  final double currentTermCredits;

  @override
  State<GpaSimulatorSheet> createState() => _GpaSimulatorSheetState();
}

class _GpaSimulatorSheetState extends State<GpaSimulatorSheet> {
  final _name = TextEditingController();
  final _credit = TextEditingController(text: '2.0');
  final _score = TextEditingController(text: '90');
  final _targetGpa = TextEditingController(text: '3.60');
  late final TextEditingController _upcomingCreds = TextEditingController(
    text: widget.currentTermCredits.toStringAsFixed(1),
  );
  final _added = <SimulatedCourse>[];
  final _excluded = <int>{};
  bool _showTargetPlanner = false;
  late List<({int index, GradeRecord record})> _gradedRecords;

  @override
  void initState() {
    super.initState();
    _gradedRecords = _buildGraded(widget.records);
  }

  @override
  void didUpdateWidget(covariant GpaSimulatorSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      _gradedRecords = _buildGraded(widget.records);
      _excluded.removeWhere((i) => i < 0 || i >= widget.records.length);
    }
  }

  static List<({int index, GradeRecord record})> _buildGraded(
    List<GradeRecord> records,
  ) => [
    for (var i = 0; i < records.length; i++)
      if (records[i].gradePoint != null && records[i].credit > 0)
        (index: i, record: records[i]),
  ];

  @override
  void dispose() {
    _name.dispose();
    _credit.dispose();
    _score.dispose();
    _targetGpa.dispose();
    _upcomingCreds.dispose();
    super.dispose();
  }

  void _addCourse() {
    final cred = double.tryParse(_credit.text.trim());
    final raw = double.tryParse(_score.text.trim());
    if (cred == null || !cred.isFinite || cred <= 0) {
      showToast(context, '请输入大于 0 的学分', success: false);
      return;
    }
    if (raw == null || !raw.isFinite || raw < 0 || raw > 100) {
      showToast(context, '请输入 0–4.0 绩点或 0–100 百分制分数', success: false);
      return;
    }
    final isGpaDirect = raw <= 4.0;
    final gp = isGpaDirect ? raw : scoreToGpa(raw);
    final score = isGpaDirect ? null : raw.clamp(0.0, 100.0);
    setState(() {
      _added.add(
        SimulatedCourse(
          name: _name.text.trim().isEmpty
              ? '假设课程 ${_added.length + 1}'
              : _name.text.trim(),
          credit: cred,
          gradePoint: gp,
          score: score,
        ),
      );
      _name.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final res = simulateGpa(
      records: widget.records,
      excludedIndices: _excluded,
      hypothetical: _added,
    );
    final delta = res.gpaDelta;
    final deltaText = delta >= 0
        ? '+${delta.toStringAsFixed(3)}'
        : delta.toStringAsFixed(3);
    final deltaColor = delta > 0.0005
        ? Colors.green
        : delta < -0.0005
        ? scheme.error
        : scheme.onSurfaceVariant;
    final plan = _showTargetPlanner
        ? planTargetGpa(
            currentGpa: res.simulatedGpa,
            currentCredits: res.simulatedCredits,
            upcomingCredits: double.tryParse(_upcomingCreds.text.trim()) ?? 0,
            targetGpa: double.tryParse(_targetGpa.text.trim()) ?? 0,
          )
        : null;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'GPA 模拟器',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _showTargetPlanner = !_showTargetPlanner,
                    ),
                    icon: Icon(
                      _showTargetPlanner
                          ? Icons.flag_rounded
                          : Icons.flag_outlined,
                      size: 18,
                    ),
                    label: const Text('目标反推'),
                  ),
                  if (_added.isNotEmpty || _excluded.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _added.clear();
                        _excluded.clear();
                      }),
                      child: const Text('重置'),
                    ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GlassCard(
                            tint: scheme.primary,
                            padding: const EdgeInsets.all(14),
                            child: HiddenValue(
                              hidden: widget.hidden,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '模拟后均绩',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        res.simulatedGpa.toStringAsFixed(3),
                                        style: theme.textTheme.headlineMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: scheme.primary,
                                            ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        deltaText,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: deltaColor,
                                            ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '原均绩 ${res.baseGpa.toStringAsFixed(3)} · '
                                    '计入 ${res.simulatedCredits.toStringAsFixed(1)} 学分'
                                    '${res.simulatedAverage != null ? ' · 加权 ${res.simulatedAverage!.toStringAsFixed(2)}' : ''}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showTargetPlanner) ...[
                            const SizedBox(height: 10),
                            GlassCard(
                              tint: scheme.tertiary,
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _targetGpa,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            labelText: '目标总均绩',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _upcomingCreds,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            labelText: '后续学分',
                                            border: OutlineInputBorder(),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      for (final preset in const [
                                        '3.40',
                                        '3.60',
                                        '3.80',
                                      ])
                                        ActionChip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text('冲 $preset'),
                                          onPressed: () {
                                            _targetGpa.text = preset;
                                            setState(() {});
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (plan == null)
                                    Text(
                                      '请输入 0–4.0 的目标均绩与大于 0 的后续学分',
                                      style: theme.textTheme.bodySmall,
                                    )
                                  else
                                    HiddenValue(
                                      hidden: widget.hidden,
                                      child: plan.alreadyReached
                                          ? Text(
                                              '当前已超过目标 ${plan.targetGpa.toStringAsFixed(2)}！',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color:
                                                        Colors.green.shade700,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            )
                                          : !plan.achievable
                                          ? Text(
                                              '需要均绩 ${plan.requiredGpa.toStringAsFixed(2)}（超过 4.0 上限），建议增加规划学分或调整目标。',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: scheme.error,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            )
                                          : Text(
                                              '接下来 ${plan.upcomingCredits.toStringAsFixed(1)} 学分平均需达到 '
                                              '${plan.requiredGpa.toStringAsFixed(2)} 绩点（约 ${plan.estimatedScore.toStringAsFixed(1)} 分）',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: scheme.primary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _name,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: '假设课程',
                                    hintText: '可选',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _credit,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: '学分',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _score,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: '分数/绩点',
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _addCourse(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _addCourse,
                                child: const Text('加入'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '输入 0–4.0 视为直接绩点，输入 >4 视为百分制自动换算（90+ 为 4.0）。',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          if (_added.isNotEmpty) ...[
                            Text('已加入假设课程', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 6),
                            for (var i = 0; i < _added.length; i++)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(_added[i].name),
                                subtitle: Text(
                                  '${formatCredit(_added[i].credit)} 学分 · 绩点 ${_added[i].gradePoint.toStringAsFixed(2)}',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () =>
                                      setState(() => _added.removeAt(i)),
                                ),
                              ),
                            const Divider(),
                          ],
                          Text(
                            '已有成绩（取消勾选可模拟排除）',
                            style: theme.textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    SliverList.builder(
                      itemCount: _gradedRecords.length,
                      itemBuilder: (context, pos) {
                        final entry = _gradedRecords[pos];
                        final i = entry.index;
                        final r = entry.record;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: !_excluded.contains(i),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _excluded.remove(i);
                            } else {
                              _excluded.add(i);
                            }
                          }),
                          title: Text(
                            r.courseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: HiddenValue(
                            hidden: widget.hidden,
                            child: Text(
                              '${formatCredit(r.credit)} 学分 · 绩点 ${r.gradePoint!.toStringAsFixed(2)}',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
