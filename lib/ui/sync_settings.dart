/// Settings for auto refresh, change alerts, exam reminders, system
/// calendar sync and `.ics` export. A bare Column of tiles; the settings
/// page mounts it inside its own group.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../app/providers.dart';
import '../app/sync_providers.dart';
import '../data/background_sync_task.dart' show backgroundRefreshSupported;
import '../data/ics_export.dart';
import '../data/timetable_diff.dart';

const _intervals = [0, 6, 12, 24];
const _alarms = [-1, 5, 10, 15, 30];

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class SyncSettings extends ConsumerWidget {
  const SyncSettings({super.key});

  void _toast(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(syncPrefsProvider);
    final ctrl = ref.read(syncPrefsProvider.notifier);
    final reminderLead = ref.watch(classReminderProvider);
    final status = ref.watch(reminderStatusProvider);
    final changes = ref.watch(timetableChangesProvider);
    final calendar = ref.watch(calendarSyncProvider);
    final calendarSupported = ref.read(calendarSyncProvider.notifier).supported;
    final cal = prefs.calendar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('自动更新'),
          subtitle: Text(
            backgroundRefreshSupported
                ? '在后台更新课表和成绩'
                : '应用打开或在托盘时更新课表和成绩',
          ),
          trailing: DropdownButton<int>(
            value: _intervals.contains(prefs.intervalHours)
                ? prefs.intervalHours
                : 12,
            underline: const SizedBox.shrink(),
            items: [
              for (final h in _intervals)
                DropdownMenuItem(
                  value: h,
                  child: Text(h == 0 ? '关闭' : '每 $h 小时'),
                ),
            ],
            onChanged: (v) {
              if (v != null) ctrl.setInterval(v);
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.edit_calendar_outlined),
          title: const Text('课表变动提醒'),
          subtitle: const Text('调课、换教室时通知'),
          value: prefs.timetableAlerts,
          onChanged: ctrl.setTimetableAlerts,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.grade_outlined),
          title: const Text('新成绩提醒'),
          subtitle: const Text('出新成绩时通知'),
          value: prefs.gradeAlerts,
          onChanged: ctrl.setGradeAlerts,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.assignment_outlined),
          title: const Text('考试提醒'),
          subtitle: Text(
            reminderLead > 0
                ? '考试前一晚 20:00 和开考前 1 小时提醒'
                : '需先开启「课前提醒」；考试前一晚 20:00 和开考前 1 小时提醒',
          ),
          value: prefs.examReminders,
          onChanged: ctrl.setExamReminders,
        ),
        if (status != null)
          ListTile(
            leading: const Icon(Icons.alarm_on_outlined),
            title: Text(status.text),
            subtitle: _isAndroid
                ? Text(status.exact ? '使用精确闹钟' : '提醒可能晚几分钟')
                : null,
            dense: true,
          ),
        if (_isAndroid) const _ExactAlarmTile(),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('最近课表变动'),
          subtitle: Text(changes.isEmpty ? '暂无记录' : '${changes.length} 条记录'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => const _ChangeLogDialog(),
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.calendar_month_outlined),
          title: const Text('系统日历同步'),
          subtitle: Text(
            calendarSupported
                ? '写入单独的「西农课表」日历'
                : '仅支持 Android 和 iOS，其他平台可导出 .ics',
          ),
          value: cal.enabled && calendarSupported,
          onChanged: calendarSupported ? ctrl.setCalendarEnabled : null,
        ),
        if (cal.enabled && calendarSupported) ...[
          ListTile(
            contentPadding: const EdgeInsetsDirectional.only(
              start: 72,
              end: 16,
            ),
            title: const Text('日程提醒'),
            trailing: DropdownButton<int>(
              value: _alarms.contains(cal.alarmMinutes) ? cal.alarmMinutes : -1,
              underline: const SizedBox.shrink(),
              items: [
                for (final m in _alarms)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m < 0 ? '不提醒' : '提前 $m 分钟'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) ctrl.setCalendarAlarm(v);
              },
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsetsDirectional.only(
              start: 72,
              end: 16,
            ),
            title: const Text('同步范围'),
            trailing: DropdownButton<String>(
              value: cal.range == '4w' ? '4w' : 'term',
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'term', child: Text('整个学期')),
                DropdownMenuItem(value: '4w', child: Text('未来 4 周')),
              ],
              onChanged: (v) {
                if (v != null) ctrl.setCalendarRange(v);
              },
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsetsDirectional.only(
              start: 72,
              end: 16,
            ),
            title: const Text('包含考试'),
            value: cal.includeExams,
            onChanged: ctrl.setCalendarIncludeExams,
          ),
          ListTile(
            contentPadding: const EdgeInsetsDirectional.only(
              start: 72,
              end: 16,
            ),
            title: const Text('立即同步'),
            subtitle: Text(
              calendar.running
                  ? '正在同步…'
                  : calendar.error ?? calendar.message ?? '课表更新后自动同步',
              style: calendar.error == null
                  ? null
                  : TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            trailing: calendar.running
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onTap: calendar.running
                ? null
                : () => ref.read(calendarSyncProvider.notifier).syncNow(),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: const Text('导出 .ics'),
          subtitle: const Text('导入其他日历应用'),
          onTap: () => _export(context, ref),
        ),
        if (backgroundRefreshSupported)
          SwitchListTile(
            secondary: const Icon(Icons.key_outlined),
            title: const Text('后台使用本设备通行密钥'),
            subtitle: const Text(
              '后台重新登录时直接使用本设备的通行密钥，不弹指纹/面容'
              '关闭时，没有保存密码就跳过后台更新',
            ),
            isThreeLine: true,
            value: prefs.backgroundUseDeviceKey,
            onChanged: ctrl.setBackgroundUseDeviceKey,
          ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final t = ref.read(timetableProvider).data;
    final id = ref.read(eduSessionProvider).account?.username;
    if (t == null || id == null) {
      _toast(context, '请先同步课表');
      return;
    }
    final options = await showDialog<({int? alarm, bool exams})>(
      context: context,
      builder: (_) => const _IcsOptionsDialog(),
    );
    if (options == null || !context.mounted) return;
    try {
      final outcome = await exportTimetableIcs(
        t: t,
        accountId: id,
        storage: ref.read(storageProvider),
        alarmMinutes: options.alarm,
        includeExams: options.exams,
      );
      if (!context.mounted) return;
      switch (outcome) {
        case IcsExportOutcome.saved:
          _toast(context, '已保存 .ics 文件');
        case IcsExportOutcome.downloaded:
          _toast(context, '已开始下载 .ics 文件');
        case IcsExportOutcome.shared || IcsExportOutcome.cancelled:
          break;
      }
    } catch (e) {
      if (context.mounted) _toast(context, '导出失败：$e');
    }
  }
}

class _ExactAlarmTile extends ConsumerWidget {
  const _ExactAlarmTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exact = ref.watch(exactAlarmProvider).valueOrNull;
    if (exact == null) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.alarm),
      title: const Text('精确提醒'),
      subtitle: Text(exact ? '已开启' : '未开启，提醒可能晚几分钟'),
      trailing: exact ? const Icon(Icons.check) : const Text('去允许'),
      onTap: exact
          ? null
          : () async {
              await ref.read(eduNotificationsProvider).requestExactAlarms();
              ref.invalidate(exactAlarmProvider);
              await ref.read(classReminderProvider.notifier).reschedule();
            },
    );
  }
}

class _IcsOptionsDialog extends StatefulWidget {
  const _IcsOptionsDialog();
  @override
  State<_IcsOptionsDialog> createState() => _IcsOptionsDialogState();
}

class _IcsOptionsDialogState extends State<_IcsOptionsDialog> {
  int _alarm = -1;
  bool _exams = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导出 .ics'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('日程提醒'),
            trailing: DropdownButton<int>(
              value: _alarm,
              underline: const SizedBox.shrink(),
              items: [
                for (final m in _alarms)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m < 0 ? '不提醒' : '提前 $m 分钟'),
                  ),
              ],
              onChanged: (v) => setState(() => _alarm = v ?? -1),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('包含考试'),
            value: _exams,
            onChanged: (v) => setState(() => _exams = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            alarm: _alarm < 0 ? null : _alarm,
            exams: _exams,
          )),
          child: const Text('导出'),
        ),
      ],
    );
  }
}

class _ChangeLogDialog extends ConsumerWidget {
  const _ChangeLogDialog();

  String _when(TimetableDiff d) {
    final l = d.at.toUtc().add(const Duration(hours: 8));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.month}月${l.day}日 ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changes = ref.watch(timetableChangesProvider);
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('最近课表变动'),
      content: SizedBox(
        width: 420,
        child: changes.isEmpty
            ? const Text('最近 20 次课表变动')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: changes.length,
                separatorBuilder: (_, _) => const Divider(height: 16),
                itemBuilder: (_, i) {
                  final d = changes[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_when(d)} · ${d.count} 处',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      for (final line in d.lines())
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(line, style: theme.textTheme.bodyMedium),
                        ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        if (changes.isNotEmpty)
          TextButton(
            onPressed: () =>
                ref.read(timetableChangesProvider.notifier).clear(),
            child: const Text('清空'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
