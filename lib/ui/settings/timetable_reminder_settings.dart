/// Timetable display preferences and class reminder lead/rule settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edu_providers.dart';
import '../../app/providers.dart';
import '../../app/sync_providers.dart';
import '../../app/ui_prefs.dart';
import '../../data/notifications.dart';
import '../widgets.dart';

/// 显示周末 / 非本周课程 / 默认视图 / 密度.
class TimetableDisplaySettings extends ConsumerWidget {
  const TimetableDisplaySettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(timetablePrefsProvider);
    final ui = ref.watch(uiPrefsProvider);
    final uiCtrl = ref.read(uiPrefsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(
          leading: Icon(Icons.view_week_outlined),
          title: Text('默认课表视图'),
          subtitle: Text('自动模式在手机竖屏用日视图、平板与桌面用周视图'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('自动'),
                selected: ui.timetableView == null,
                onSelected: (_) => uiCtrl.setTimetableView(null),
              ),
              ChoiceChip(
                label: const Text('日视图'),
                selected: ui.timetableView == TimetableViewMode.day,
                onSelected: (_) =>
                    uiCtrl.setTimetableView(TimetableViewMode.day),
              ),
              ChoiceChip(
                label: const Text('周视图'),
                selected: ui.timetableView == TimetableViewMode.week,
                onSelected: (_) =>
                    uiCtrl.setTimetableView(TimetableViewMode.week),
              ),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.weekend_outlined),
          title: const Text('显示周末'),
          value: prefs.showWeekend,
          onChanged: ref.read(timetablePrefsProvider.notifier).setShowWeekend,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.layers_outlined),
          title: const Text('显示非本周课程'),
          subtitle: const Text('斜纹淡色显示'),
          value: prefs.showOtherWeeks,
          onChanged: ref
              .read(timetablePrefsProvider.notifier)
              .setShowOtherWeeks,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.density_small_outlined),
          title: const Text('紧凑行高'),
          subtitle: const Text('同屏显示更多节次，减少上下滚动'),
          value: ui.compactTimetable,
          onChanged: uiCtrl.setCompactTimetable,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.person_outline),
          title: const Text('周视图显示授课教师'),
          value: ui.showTeacher,
          onChanged: uiCtrl.setShowTeacher,
        ),
      ],
    );
  }
}

/// 课前提醒: how long before, the first class of the day, same-room and
/// building-change rules.
class ReminderSettings extends ConsumerStatefulWidget {
  const ReminderSettings({super.key});

  @override
  ConsumerState<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends ConsumerState<ReminderSettings> {
  Future<void> _setLead(int minutes) async {
    try {
      await ref.read(classReminderProvider.notifier).setLead(minutes);
    } catch (_) {
      if (mounted) {
        showToast(context, '没有通知权限：请在系统设置里允许本应用发送通知。', success: false);
      }
    }
  }

  Future<void> _update(Future<void> Function() save) async {
    await save();
    if (!mounted) return;
    await ref.read(classReminderProvider.notifier).reschedule();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lead = ref.watch(classReminderProvider);
    final storage = ref.watch(storageProvider);
    final first = storage.firstClassReminderMinutes();
    final status = ref.watch(reminderStatusProvider);
    final on = lead > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('课前提醒'),
          subtitle: Text(
            !on
                ? '关闭'
                : status == null
                ? '提前 $lead 分钟'
                : '提前 $lead 分钟 · 已安排 ${status.count} 条',
          ),
          value: on,
          onChanged: (v) => _setLead(v ? 10 : 0),
        ),
        if (on) ...[
          _MinutesRow(
            label: '提前多久',
            value: lead,
            min: 1,
            max: 120,
            onChanged: _setLead,
          ),
          _MinutesRow(
            label: '每天第一节',
            hint: '从宿舍出发通常要更早',
            value: first,
            min: 0,
            max: 120,
            zeroLabel: '同上',
            onChanged: (v) =>
                _update(() => storage.setFirstClassReminderMinutes(v)),
          ),
          SwitchListTile(
            title: const Text('连堂同一教室不提醒'),
            subtitle: const Text('下课就在这间，不用再提醒'),
            value: storage.reminderSkipSameRoom(),
            onChanged: (v) => _update(() => storage.setReminderSkipSameRoom(v)),
          ),
          SwitchListTile(
            title: const Text('换楼时下课就提醒'),
            subtitle: const Text('下一节在别的楼，上一节一结束就提醒你动身'),
            value: storage.reminderBuildingChange(),
            onChanged: (v) =>
                _update(() => storage.setReminderBuildingChange(v)),
          ),
          if (!NotificationService.instance.canSchedule)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('这个平台只能在应用打开或在托盘时提醒。'),
            ),
        ],
      ],
    );
  }
}

/// A minutes value with − / + buttons and quick steps.
class _MinutesRow extends StatelessWidget {
  const _MinutesRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.hint,
    this.zeroLabel,
  });
  final String label;
  final String? hint;
  final int value;
  final int min;
  final int max;
  final String? zeroLabel;
  final ValueChanged<int> onChanged;

  int _prevStep() {
    if (value <= min) return min;
    if (value > 30) {
      final snapped = ((value - 1) ~/ 10) * 10;
      return snapped.clamp(min, max);
    }
    if (value > 5) {
      final snapped = ((value - 1) ~/ 5) * 5;
      return snapped.clamp(min, max);
    }
    return min;
  }

  int _nextStep() {
    if (value >= max) return max;
    if (value >= 30) {
      final snapped = ((value ~/ 10) + 1) * 10;
      return snapped.clamp(min, max);
    }
    final snapped = ((value ~/ 5) + 1) * 5;
    return snapped.clamp(min, max);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: '减少',
            onPressed: value > min ? () => onChanged(_prevStep()) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 64,
            child: Text(
              value == 0 && zeroLabel != null ? zeroLabel! : '$value 分钟',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: '增加',
            onPressed: value < max ? () => onChanged(_nextStep()) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
