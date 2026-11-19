/// Native seminar room booking sheet: real room photo, visual day timeline,
/// auto-clamped duration chips (1h..max 4h) + RangeSlider, teammate lookup,
/// remembered phone number, and AES-encrypted submit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors.dart';
import '../../data/library_service.dart';
import '../widgets.dart';
import '../widgets/glass.dart';
import 'library_common.dart';
import 'library_media.dart';

class SeminarBookSheet extends ConsumerStatefulWidget {
  const SeminarBookSheet({super.key, required this.area});
  final LibraryArea area;

  @override
  ConsumerState<SeminarBookSheet> createState() => _SeminarBookSheetState();
}

class _SeminarBookSheetState extends ConsumerState<SeminarBookSheet> {
  static const _kSavedMobile = 'ui.lib_mobile.v1';

  List<String>? _dates;
  int _dateIndex = 0;
  LibrarySeminarDay? _dayInfo;
  List<(int, int)> _bookedRangesMin = const [];
  bool _loadingDay = false;
  bool _submitting = false;
  bool _addingMember = false;
  String? _errorText;
  String? _dayErrorText;

  /// Selected range in minutes from midnight (snapped to 15-min intervals,
  /// matching NWAFU's official booking step).
  static const _kStepMin = 15;
  int _startMin = 8 * 60;
  int _endMin = 12 * 60;
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _mobile = TextEditingController();
  final _card = TextEditingController();
  final _members = <LibraryTeamMember>[];
  int _dayLoadSeq = 0;

  @override
  void initState() {
    super.initState();
    _restoreMobile();
    _loadDates();
  }

  Future<void> _restoreMobile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kSavedMobile);
      if (saved != null &&
          saved.isNotEmpty &&
          mounted &&
          _mobile.text.isEmpty) {
        _mobile.text = saved;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _mobile.dispose();
    _card.dispose();
    super.dispose();
  }

  static int _toMin(String hhmm, int fallback) {
    final p = hhmm.split(':');
    final h = int.tryParse(p.first);
    final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    if (h == null) return fallback;
    return h * 60 + m;
  }

  static String _fmtMin(int minutes) {
    final h = (minutes ~/ 60).clamp(0, 23).toString().padLeft(2, '0');
    final m = (minutes % 60).clamp(0, 59).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _startTime => _fmtMin(_startMin);
  String get _endTime => _fmtMin(_endMin);

  bool _hasBookedConflict(int start, int end) {
    for (final (s, e) in _bookedRangesMin) {
      if (start < e && end > s) return true;
    }
    return false;
  }

  static String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m 分钟';
    if (m == 0) return '$h 小时';
    return '$h 小时 $m 分钟';
  }

  /// Picks the first non-conflicting window of up to [preferredMinutes]
  /// (defaulting to maxDurationMinutes, typically 4 hours).
  void _pickSmartWindow(LibrarySeminarDay info, {int? preferredMinutes}) {
    final openMin = _toMin(info.openStart, 8 * 60);
    final closeMin = _toMin(info.openEnd, 22 * 60);
    if (closeMin <= openMin) {
      _startMin = openMin;
      _endMin = openMin;
      return;
    }
    final availSpan = closeMin - openMin;
    final minDur = info.minDurationMinutes.clamp(15, 240).clamp(1, availSpan);
    final maxDur = info.maxDurationMinutes.clamp(minDur, 480);
    final target = (preferredMinutes ?? maxDur).clamp(minDur, maxDur);

    // If booking today, don't start in the past (snap up to next 15-min mark).
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    var earliest = openMin;
    if (info.day == todayStr) {
      final nowMin = now.hour * 60 + now.minute;
      final snapped = ((nowMin + _kStepMin - 1) ~/ _kStepMin) * _kStepMin;
      if (snapped > earliest) earliest = snapped;
    }

    // Try to find the earliest free slot of [target] length, else [minDur].
    for (final dur in [target, minDur]) {
      for (var s = earliest; s + dur <= closeMin; s += _kStepMin) {
        if (!_hasBookedConflict(s, s + dur)) {
          _startMin = s;
          _endMin = s + dur;
          return;
        }
      }
    }
    final maxStart = (closeMin - minDur).clamp(openMin, closeMin);
    _startMin = earliest.clamp(openMin, maxStart);
    final lowerEnd = (_startMin + minDur).clamp(_startMin, closeMin);
    _endMin = (_startMin + target).clamp(lowerEnd, closeMin);
  }

  /// Applies a quick duration (e.g. 30/60/120/180/240 min) from current start,
  /// automatically clamping to closing time and max duration.
  void _applyDuration(int minutes) {
    final info = _dayInfo;
    if (info == null) return;
    final openMin = _toMin(info.openStart, 8 * 60);
    final closeMin = _toMin(info.openEnd, 22 * 60);
    if (closeMin <= openMin) return;
    var s = _startMin.clamp(
      openMin,
      (closeMin - _kStepMin).clamp(openMin, closeMin),
    );
    var e = s + minutes;
    if (e > closeMin) {
      e = closeMin;
      s = (e - minutes).clamp(
        openMin,
        (e - _kStepMin).clamp(openMin, closeMin),
      );
    }
    setState(() {
      _startMin = s;
      _endMin = e;
    });
  }

  Future<void> _loadDates() async {
    setState(() {
      _dates = null;
      _dayInfo = null;
      _bookedRangesMin = const [];
      _errorText = null;
      _dayErrorText = null;
    });
    try {
      final dates = await ref
          .read(libraryServiceProvider)
          .seminarDates(widget.area.id);
      if (!mounted) return;
      setState(() {
        _dates = dates;
        _dateIndex = 0;
      });
      if (dates.isNotEmpty) await _loadDay();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e is AppError ? e.message : '无法加载研讨室可预约日期';
      });
    }
  }

  Future<void> _loadDay() async {
    final dates = _dates;
    if (dates == null || dates.isEmpty) return;
    final day = dates[_dateIndex.clamp(0, dates.length - 1)];
    final seq = ++_dayLoadSeq;
    setState(() {
      _loadingDay = true;
      _dayInfo = null;
      _bookedRangesMin = const [];
      _dayErrorText = null;
    });
    try {
      final info = await ref
          .read(libraryServiceProvider)
          .seminarDay(
            roomId: widget.area.id,
            areaId: widget.area.parentId.isNotEmpty
                ? widget.area.parentId
                : widget.area.id,
            day: day,
          );
      if (!mounted || seq != _dayLoadSeq) return;
      final openMin = _toMin(info.openStart, 8 * 60);
      final parsedBooked = [
        for (final (bs, be) in info.bookedRanges)
          (_toMin(bs, openMin), _toMin(be, openMin)),
      ];
      setState(() {
        _dayInfo = info;
        _bookedRangesMin = parsedBooked;
        _loadingDay = false;
        _pickSmartWindow(info);
      });
    } catch (e) {
      if (!mounted || seq != _dayLoadSeq) return;
      final msg = e is AppError ? e.message : '无法加载该日研讨室时段信息';
      setState(() {
        _loadingDay = false;
        _dayErrorText = msg;
      });
      showToast(context, msg, success: false);
    }
  }

  Future<void> _addMember() async {
    final card = _card.text.trim();
    if (card.isEmpty || _addingMember || _submitting) return;
    final maxP = _dayInfo?.maxPerson ?? widget.area.capacity ?? 10;
    if (_members.length + 1 >= maxP) {
      showToast(context, '已达到最大参与人数 ($maxP 人)');
      return;
    }
    setState(() => _addingMember = true);
    try {
      final dates = _dates;
      final day = dates != null && dates.isNotEmpty
          ? dates[_dateIndex.clamp(0, dates.length - 1)]
          : '';
      final member = await ref
          .read(libraryServiceProvider)
          .lookupSeminarMember(
            card: card,
            areaId: widget.area.id,
            beginTime: day.isNotEmpty ? '$day $_startTime' : null,
            endTime: day.isNotEmpty ? '$day $_endTime' : null,
          );
      if (!mounted) return;
      if (_members.any((m) => m.id == member.id)) {
        showToast(context, '该成员已在列表中');
      } else {
        setState(() {
          _members.add(member);
          _card.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, e is AppError ? e.message : '查询成员失败', success: false);
    } finally {
      if (mounted) setState(() => _addingMember = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _dates == null || _dates!.isEmpty) return;
    final info = _dayInfo;
    if (info == null) {
      showToast(context, '请等待该日时段信息加载完成', success: false);
      return;
    }
    final minP = info.minPerson;
    if (_members.length + 1 < minP) {
      showToast(context, '至少还需要添加 ${minP - 1 - _members.length} 名参与成员');
      return;
    }
    final title = _title.text.trim();
    final content = _content.text.trim();
    final mobile = _mobile.text.trim();
    if (title.isEmpty) {
      showToast(context, '请填写预约主题');
      return;
    }
    if (content.isEmpty) {
      showToast(context, '请填写使用内容');
      return;
    }
    if (mobile.isEmpty) {
      showToast(context, '请填写联系电话');
      return;
    }
    if (_endMin <= _startMin) {
      showToast(context, '结束时间需晚于开始时间');
      return;
    }
    if (_hasBookedConflict(_startMin, _endMin)) {
      showToast(context, '所选时段与已有预约冲突，请调整时间');
      return;
    }
    final day = _dates![_dateIndex.clamp(0, _dates!.length - 1)];
    final startTime = _startTime;
    final endTime = _endTime;
    final teamIds = [for (final m in _members) m.id];

    setState(() => _submitting = true);
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kSavedMobile, mobile);
      } catch (_) {}
      if (!mounted) return;
      final msg = await ref
          .read(libraryServiceProvider)
          .bookSeminar(
            roomId: widget.area.id,
            day: day,
            startTime: startTime,
            endTime: endTime,
            title: title,
            content: content,
            mobile: mobile,
            teamUserIds: teamIds,
          );
      if (!mounted) return;
      showToast(context, msg, success: true);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        e is AppError ? e.message : '研讨室预约失败',
        success: false,
      );
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = _dayInfo;
    final openMin = info == null ? 8 * 60 : _toMin(info.openStart, 8 * 60);
    final closeMin = info == null ? 22 * 60 : _toMin(info.openEnd, 22 * 60);
    final minDur = (info?.minDurationMinutes ?? 60).clamp(15, 240);
    final maxDur = (info?.maxDurationMinutes ?? 240).clamp(minDur, 480);
    final durMin = (_endMin - _startMin).clamp(0, 24 * 60);
    final durLabel = _fmtDuration(durMin);
    final maxHoursLabel = _fmtDuration(maxDur);
    final conflict = _hasBookedConflict(_startMin, _endMin);
    final minNeed = ((info?.minPerson ?? 1) - 1).clamp(0, 99);
    final quickMinutes = [
      for (final m in const [30, 60, 120, 180, 240])
        if (m >= minDur && m <= maxDur) m,
    ];
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.area.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            widget.area.campus,
                            widget.area.floor,
                            if (info != null)
                              '${info.minPerson}–${info.maxPerson} 人',
                            if (info != null)
                              '开放 ${info.openStart}–${info.openEnd}',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_dates == null && _errorText == null)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorText != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorText!),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loadDates,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_dates!.isEmpty)
                const Expanded(child: Center(child: Text('当前没有可预约的日期')))
              else
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      if (widget.area.imageUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 152,
                            child: LibraryImage(
                              url: widget.area.imageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (widget.area.description.isNotEmpty) ...[
                        Text(
                          widget.area.description,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                      ],
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < _dates!.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(_dates![i]),
                                  selected: i == _dateIndex,
                                  onSelected: _submitting
                                      ? null
                                      : (_) {
                                          setState(() => _dateIndex = i);
                                          _loadDay();
                                        },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loadingDay)
                        const LinearProgressIndicator()
                      else if (_dayErrorText != null && info == null)
                        GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(_dayErrorText!),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _loadDay,
                                child: const Text('重试加载当日时段'),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        GlassCard(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                          tint: conflict ? scheme.error : scheme.primary,
                          tintAmount: 0.06,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$_startTime – $_endTime · 共 $durLabel',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: conflict
                                                ? scheme.error
                                                : scheme.primary,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '上限 $maxHoursLabel',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _SeminarTimelineBar(
                                openMin: openMin,
                                closeMin: closeMin,
                                startMin: _startMin,
                                endMin: _endMin,
                                bookedRanges: _bookedRangesMin,
                                conflict: conflict,
                              ),
                              if (info != null &&
                                  info.bookedRanges.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '已约时段：${info.bookedRanges.map((r) => '${r.$1}–${r.$2}').join('、')}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (closeMin > openMin)
                                RangeSlider(
                                  min: openMin.toDouble(),
                                  max: closeMin.toDouble(),
                                  divisions: ((closeMin - openMin) ~/ _kStepMin)
                                      .clamp(1, 96),
                                  values: RangeValues(
                                    _startMin
                                        .clamp(openMin, closeMin)
                                        .toDouble(),
                                    _endMin
                                        .clamp(openMin, closeMin)
                                        .toDouble(),
                                  ),
                                  labels: RangeLabels(_startTime, _endTime),
                                  onChanged: _submitting
                                      ? null
                                      : (v) {
                                          var s =
                                              (v.start / _kStepMin).round() *
                                              _kStepMin;
                                          var e =
                                              (v.end / _kStepMin).round() *
                                              _kStepMin;
                                          if (e - s < minDur) {
                                            if (s != _startMin) {
                                              e = (s + minDur).clamp(
                                                openMin,
                                                closeMin,
                                              );
                                              s = (e - minDur).clamp(
                                                openMin,
                                                closeMin,
                                              );
                                            } else {
                                              s = (e - minDur).clamp(
                                                openMin,
                                                closeMin,
                                              );
                                            }
                                          } else if (e - s > maxDur) {
                                            if (s != _startMin) {
                                              e = s + maxDur;
                                            } else {
                                              s = e - maxDur;
                                            }
                                          }
                                          setState(() {
                                            _startMin = s.clamp(
                                              openMin,
                                              closeMin,
                                            );
                                            _endMin = e.clamp(
                                              openMin,
                                              closeMin,
                                            );
                                          });
                                        },
                                ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final m in quickMinutes)
                                    ChoiceChip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(_fmtDuration(m)),
                                      selected: durMin == m,
                                      onSelected: _submitting
                                          ? null
                                          : (_) => _applyDuration(m),
                                    ),
                                ],
                              ),
                              if (conflict) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '与当日已约时段重叠，请拖动滑块避开灰色区间',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _title,
                          enabled: !_submitting,
                          decoration: const InputDecoration(
                            labelText: '预约主题',
                            hintText: '例如：小组课程讨论',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _content,
                          enabled: !_submitting,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: '使用内容',
                            hintText: '简述研讨内容',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _mobile,
                          enabled: !_submitting,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: '联系电话（自动记住）',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          minNeed > 0
                              ? '参与成员（含本人至少 ${info!.minPerson} 人，还需添加 ${(minNeed - _members.length).clamp(0, 99)} 人）'
                              : '参与成员（可选）',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _card,
                                enabled: !_submitting && !_addingMember,
                                decoration: const InputDecoration(
                                  hintText: '输入同伴学号',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _addMember(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: _addingMember || _submitting
                                  ? null
                                  : _addMember,
                              child: Text(_addingMember ? '查询中…' : '添加'),
                            ),
                          ],
                        ),
                        if (_members.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final m in _members)
                                InputChip(
                                  label: Text('${m.name} (${m.card})'),
                                  onDeleted: _submitting
                                      ? null
                                      : () => setState(
                                          () => _members.removeWhere(
                                            (x) => x.id == m.id,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed:
                              _submitting || conflict || info == null
                              ? null
                              : _submit,
                          child: Text(_submitting ? '提交中…' : '确认预约研讨室'),
                        ),
                      ],
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

class _SeminarTimelineBar extends StatelessWidget {
  const _SeminarTimelineBar({
    required this.openMin,
    required this.closeMin,
    required this.startMin,
    required this.endMin,
    required this.bookedRanges,
    required this.conflict,
  });

  final int openMin;
  final int closeMin;
  final int startMin;
  final int endMin;
  final List<(int, int)> bookedRanges;
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final span = (closeMin - openMin).clamp(1, 24 * 60);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double x(int m) => ((m - openMin) / span).clamp(0.0, 1.0) * w;
        final selLeft = x(startMin);
        final selWidth = (x(endMin) - selLeft).clamp(2.0, w);
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: scheme.surfaceContainerHighest),
                for (final (bs, be) in bookedRanges)
                  Positioned(
                    left: x(bs),
                    width: (x(be) - x(bs)).clamp(2.0, w),
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: scheme.outline.withValues(alpha: 0.45),
                    ),
                  ),
                Positioned(
                  left: selLeft,
                  width: selWidth,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: (conflict ? scheme.error : scheme.primary)
                        .withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
