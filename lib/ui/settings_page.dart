/// Settings: appearance, monitor cadence, captcha recognition, accounts,
/// server, notifications, diagnostics.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../app/providers.dart';
import '../app/sync_providers.dart';
import '../app/theme.dart';
import '../app/ui_prefs.dart';
import '../data/background.dart';
import '../data/http_ocr_solver.dart';
import '../data/notifications.dart';
import '../data/storage.dart';
import 'diagnostics_page.dart';
import 'edu_login_page.dart';
import 'layout.dart';
import 'login_page.dart';
import 'update_widgets.dart';
import 'widgets.dart';
import 'widgets/glass.dart';
import 'account_access_settings.dart';
import 'sync_settings.dart';

/// A top-level category in [SettingsScreen].
class _SettingsCategory {
  const _SettingsCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;
}

/// 设置, reached from 我的. [section] opens a specific category directly
/// (e.g. '版本与更新').
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.section});
  final String? section;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late int _selectedIndex;

  List<_SettingsCategory> _categories() => const [
    _SettingsCategory(
      id: '账号与安全',
      title: '账号与安全',
      subtitle: kIsWeb ? '教务会话、选课账号' : '统一身份认证、通行密钥、校外访问、选课账号',
      icon: Icons.shield_outlined,
      children: [
        _EduSettings(),
        if (!kIsWeb) DeviceSignInSetting(),
        if (!kIsWeb) CampusAccessSetting(),
        _Accounts(),
      ],
    ),
    _SettingsCategory(
      id: '课表与提醒',
      title: '课表与提醒',
      subtitle: kIsWeb ? '视图密度、课程显示、导出 .ics' : '视图密度、课前提醒、后台同步与日历',
      icon: Icons.calendar_month_outlined,
      children: [
        _TimetableDisplay(),
        if (!kIsWeb) _ReminderSettings(),
        SyncSettings(),
      ],
    ),
    _SettingsCategory(
      id: '外观',
      title: '外观与缩放',
      subtitle: '深浅主题、界面缩放、文字大小、玻璃效果',
      icon: Icons.palette_outlined,
      children: [_Appearance()],
    ),
    _SettingsCategory(
      id: '选课与抢课',
      title: '选课与抢课',
      subtitle: '监控间隔、自动重登、验证码识别',
      icon: Icons.bolt_outlined,
      children: [_MonitorSettings(), _SilentReloginSetting(), _OcrSettings()],
    ),
    _SettingsCategory(
      id: '后台与通知',
      title: kIsWeb ? '通知' : '后台与保活',
      subtitle: kIsWeb ? '浏览器桌面通知' : '关闭最小化到托盘、防休眠、前台服务',
      icon: Icons.notifications_active_outlined,
      children: [
        if (!kIsWeb) _BackgroundSettings(),
        if (kIsWeb) _BrowserNotificationSetting(),
      ],
    ),
    _SettingsCategory(
      id: '版本与更新',
      title: '关于与高级',
      subtitle: '检查更新、服务器地址、连接诊断',
      icon: Icons.tune_outlined,
      children: [
        UpdateSettings(),
        ServerOriginSetting(),
        _DiagnosticsEntry(),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    final cats = _categories();
    final target = widget.section;
    final idx = target == null
        ? 0
        : cats.indexWhere((c) => c.id == target || c.title == target);
    _selectedIndex = idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categories();
    final selected = cats[_selectedIndex.clamp(0, cats.length - 1)];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            widget.section != null && MediaQuery.sizeOf(context).width < 800
                ? selected.title
                : '设置',
          ),
          backgroundColor: Colors.transparent,
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            // Desktop / tablet: master-detail split view.
            if (w >= 800) {
              const maxW = 1120.0;
              final side = ((w - maxW) / 2).clamp(20.0, double.infinity);
              return Padding(
                padding: EdgeInsets.fromLTRB(side, 8, side, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 248,
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: cats.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 48, endIndent: 12),
                          itemBuilder: (context, i) {
                            final c = cats[i];
                            final active = i == _selectedIndex;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              child: ListTile(
                                selected: active,
                                selectedTileColor: scheme.primary.withValues(
                                  alpha: 0.14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                leading: Icon(
                                  c.icon,
                                  color: active
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                title: Text(
                                  c.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: active ? scheme.primary : null,
                                  ),
                                ),
                                onTap: () =>
                                    setState(() => _selectedIndex = i),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: _CategoryBody(category: selected),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Phone: direct sub-view if opened with a specific section;
            // otherwise a clean categorized index list.
            final gutter = pageGutter(w);
            if (widget.section != null) {
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
                child: _CategoryBody(category: selected),
              );
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < cats.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(cats[i].icon, color: scheme.primary),
                          title: Text(cats[i].title),
                          subtitle: Text(
                            cats[i].subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  _SettingsCategoryScreen(category: cats[i]),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsCategoryScreen extends StatelessWidget {
  const _SettingsCategoryScreen({required this.category});
  final _SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    final gutter = pageGutter(MediaQuery.sizeOf(context).width);
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(category.title),
          backgroundColor: Colors.transparent,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kReadableMaxWidth),
              child: _CategoryBody(category: category),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryBody extends StatelessWidget {
  const _CategoryBody({required this.category});
  final _SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    return _Group(title: category.title, children: category.children);
  }
}

class _EduSettings extends ConsumerWidget {
  const _EduSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(eduSessionProvider);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(session.account?.displayName ?? '登录统一身份认证'),
          subtitle: Text(
            session.signedIn
                ? [
                    session.account!.username,
                    session.account!.major,
                  ].where((s) => s.isNotEmpty).join(' · ')
                : '登录后同步课表、成绩',
          ),
          trailing: session.signedIn
              ? TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('退出教务账号？'),
                        content: const Text('会删除本机的课表、成绩和登录信息，并取消课前提醒。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('退出并清除'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref.read(eduSessionProvider.notifier).logout();
                    }
                  },
                  child: const Text('退出'),
                )
              : const Icon(Icons.chevron_right),
          onTap: session.signedIn
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const EduLoginPage()),
                ),
        ),
      ],
    );
  }
}

/// 显示周末 / 非本周课程.
class _TimetableDisplay extends ConsumerWidget {
  const _TimetableDisplay();

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
                onSelected: (_) => uiCtrl.setTimetableView(TimetableViewMode.day),
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
class _ReminderSettings extends ConsumerStatefulWidget {
  const _ReminderSettings();

  @override
  ConsumerState<_ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends ConsumerState<_ReminderSettings> {
  Future<void> _setLead(int minutes) async {
    try {
      await ref.read(classReminderProvider.notifier).setLead(minutes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有通知权限：请在系统设置里允许本应用发送通知。')),
        );
      }
    }
  }

  Future<void> _update(Future<void> Function() save) async {
    await save();
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

/// A minutes value with − / + buttons and quick presets.
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

class _Appearance extends ConsumerWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final ctrl = ref.read(themeControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final custom =
        !theme.useDynamic &&
        !kSeedPresets.any((p) => p.$2.toARGB32() == theme.seed.toARGB32());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          leading: Icon(Icons.brightness_6_outlined),
          title: Text('显示模式'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (mode, label) in [
                (ThemeMode.system, '系统'),
                (ThemeMode.light, '浅色'),
                (ThemeMode.dark, '深色'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: theme.mode == mode,
                  onSelected: (_) => ctrl.setMode(mode),
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.aspect_ratio_outlined),
          title: Text('界面缩放 · ${ref.watch(uiScaleModeProvider).label}'),
          subtitle: const Text('自动模式会在小屏手机、横屏与高分大屏上智能调整密度与比例'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in UiScaleMode.values)
                ChoiceChip(
                  label: Text(mode.label),
                  selected: ref.watch(uiScaleModeProvider) == mode,
                  onSelected: (_) =>
                      ref.read(uiPrefsProvider.notifier).setScaleMode(mode),
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: Text('文字大小 ${(ref.watch(textScaleProvider) * 100).round()}%'),
          subtitle: const Text('叠加系统字体大小；4K 屏可适当调大。'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scale in [0.85, 1.0, 1.15, 1.3, 1.45, 1.6])
                ChoiceChip(
                  label: Text('${(scale * 100).round()}%'),
                  selected: (ref.watch(textScaleProvider) - scale).abs() < 0.01,
                  onSelected: (_) =>
                      ref.read(textScaleProvider.notifier).set(scale),
                ),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.blur_on),
          title: const Text('玻璃效果'),
          subtitle: const Text('半透明导航与卡片；关闭后使用纯色表面，更省电'),
          value: ref.watch(glassEnabledProvider),
          onChanged: ref.read(uiPrefsProvider.notifier).setGlass,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          title: const Text('跟随系统强调色'),
          value: theme.useDynamic,
          onChanged: ctrl.setUseDynamic,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Opacity(
            opacity: theme.useDynamic ? 0.4 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题色', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (name, c) in kSeedPresets)
                      _Swatch(
                        color: c,
                        tooltip: name,
                        selected:
                            !theme.useDynamic &&
                            theme.seed.toARGB32() == c.toARGB32(),
                        onTap: () => ctrl.setSeed(c),
                      ),
                    _Swatch(
                      color: custom ? theme.seed : null,
                      tooltip: '自定义',
                      selected: custom,
                      onTap: () => _pickCustom(context, ref, theme.seed),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCustom(
    BuildContext context,
    WidgetRef ref,
    Color initial,
  ) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _HuePickerDialog(initial: initial),
    );
    if (picked != null) {
      await ref.read(themeControllerProvider.notifier).setSeed(picked);
    }
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });
  final Color? color;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: color,
            gradient: color == null
                ? const SweepGradient(
                    colors: [
                      Colors.red,
                      Colors.yellow,
                      Colors.green,
                      Colors.cyan,
                      Colors.blue,
                      Colors.purple,
                      Colors.red,
                    ],
                  )
                : null,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : color == null
              ? const Icon(Icons.add, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

/// Hue / saturation / lightness sliders with a live preview.
class _HuePickerDialog extends StatefulWidget {
  const _HuePickerDialog({required this.initial});
  final Color initial;

  @override
  State<_HuePickerDialog> createState() => _HuePickerDialogState();
}

class _HuePickerDialogState extends State<_HuePickerDialog> {
  late HSLColor _hsl = HSLColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsl.toColor();
    final scheme = ColorScheme.fromSeed(
      seedColor: color,
      brightness: Theme.of(context).brightness,
    );
    Widget slider(
      String label,
      double value,
      double max,
      ValueChanged<double> onChanged,
    ) {
      return Row(
        children: [
          SizedBox(width: 40, child: Text(label)),
          Expanded(
            child: Slider(value: value, max: max, onChanged: onChanged),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('自定义主题色'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            slider(
              '色相',
              _hsl.hue,
              360,
              (v) => setState(() => _hsl = _hsl.withHue(v)),
            ),
            slider(
              '饱和度',
              _hsl.saturation,
              1,
              (v) => setState(() => _hsl = _hsl.withSaturation(v)),
            ),
            slider(
              '明度',
              _hsl.lightness,
              1,
              (v) => setState(() => _hsl = _hsl.withLightness(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('使用'),
        ),
      ],
    );
  }
}

/// Signed-in accounts (switch / sign out), saved accounts (forget), add.
class _Accounts extends ConsumerWidget {
  const _Accounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(signedInAccountsProvider);
    final activeId = ref.watch(activeAccountIdProvider);
    final saved = ref.watch(accountsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in signedIn)
          Builder(
            builder: (context) {
              final s = ref.watch(sessionControllerProvider(id));
              final expired = s.phase == AuthPhase.expired;
              return ListTile(
                leading: Icon(
                  id == activeId
                      ? Icons.account_circle
                      : Icons.account_circle_outlined,
                  color: expired ? scheme.error : null,
                ),
                title: Text(s.displayName),
                subtitle: Text(
                  [
                    id,
                    if (s.activeBatch != null) s.activeBatch!.name,
                    if (expired) '登录已失效',
                  ].join('  '),
                ),
                trailing: TextButton(
                  onPressed: () => _signOut(context, ref, id, s.displayName),
                  child: const Text('退出'),
                ),
                onTap: id == activeId
                    ? null
                    : () =>
                          ref.read(activeAccountIdProvider.notifier).state = id,
              );
            },
          ),
        for (final a in saved)
          if (!signedIn.contains(a.id))
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(a.displayName),
              subtitle: Text('${a.loginName}  未登录'),
              trailing: IconButton(
                tooltip: '删除账号和密码',
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    ref.read(accountsProvider.notifier).remove(a.id),
              ),
            ),

        SwitchListTile(
          secondary: const Icon(Icons.tab_outlined),
          title: const Text('多账号'),
          subtitle: const Text('同时登录多个账号，以标签页切换，各自监控'),
          value: ref.watch(multiAccountProvider),
          onChanged: (v) => ref.read(multiAccountProvider.notifier).set(v),
        ),
        if (ref.watch(multiAccountProvider))
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LoginPage(addingAccount: true),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('添加账号'),
            ),
          ),
      ],
    );
  }

  Future<void> _signOut(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final running = ref.read(sessionScopeProvider(id)).engine.isRunning;
    if (running) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('退出 $name'),
          content: const Text('该账号的监控正在运行，退出后会停止。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await leaveAccount(ref, id);
  }
}

/// How hard the app tries to recover a dropped session on its own before
/// asking the user (each attempt = one captcha fetch + OCR + login).
class _SilentReloginSetting extends ConsumerStatefulWidget {
  const _SilentReloginSetting();

  @override
  ConsumerState<_SilentReloginSetting> createState() =>
      _SilentReloginSettingState();
}

class _SilentReloginSettingState extends ConsumerState<_SilentReloginSetting> {
  @override
  Widget build(BuildContext context) {
    final attempts = ref.watch(silentReloginAttemptsProvider);
    final enabled = ref.watch(silentReloginEnabledProvider);
    final guard = ref.watch(contestedGuardProvider);
    final guardMinutes = ref.watch(contestedWindowMinutesProvider);
    final unlimited = attempts < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.autorenew),
          title: const Text('掉线后自动重新登录'),
          subtitle: Text(
            !enabled
                ? '关闭，掉线后直接弹窗'
                : unlimited
                ? '不限次数，间隔逐步拉长'
                : '验证码最多识别 $attempts 次，仍失败再弹窗并说明原因',
          ),
          value: enabled,
          onChanged: (v) =>
              ref.read(silentReloginEnabledProvider.notifier).set(v),
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                const Expanded(child: Text('最多试几次')),
                IconButton.filledTonal(
                  tooltip: '减少',
                  onPressed: !unlimited && attempts > 1
                      ? () => ref
                            .read(silentReloginAttemptsProvider.notifier)
                            .set(attempts - 1)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    unlimited ? '不限' : '$attempts 次',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '增加',
                  onPressed: !unlimited && attempts < 10
                      ? () => ref
                            .read(silentReloginAttemptsProvider.notifier)
                            .set(attempts + 1)
                      : null,
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('不限'),
                  selected: unlimited,
                  onSelected: (v) => ref
                      .read(silentReloginAttemptsProvider.notifier)
                      .set(v ? -1 : 3),
                ),
              ],
            ),
          ),
        if (enabled)
          SwitchListTile(
            secondary: const Icon(Icons.swap_horiz),
            title: const Text('被踢下线时让步'),
            subtitle: Text(
              guard
                  ? '重新登录后 $guardMinutes 分钟内再次被踢就不再抢回会话，改为弹窗'
                  : '关闭：每次被踢都自动重新登录，把别处的会话踢掉',
            ),
            value: guard,
            onChanged: (v) => ref.read(contestedGuardProvider.notifier).set(v),
          ),
        if (enabled && guard)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Text('让步时间窗'),
                Expanded(
                  child: Slider(
                    value: guardMinutes.toDouble().clamp(1, 30),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '$guardMinutes 分钟',
                    onChanged: (v) => ref
                        .read(contestedWindowMinutesProvider.notifier)
                        .set(v.round()),
                  ),
                ),
                Text('$guardMinutes 分钟'),
              ],
            ),
          ),
      ],
    );
  }
}

/// Keep-alive switches; the platform decides what each one means.
class _BackgroundSettings extends ConsumerWidget {
  const _BackgroundSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return const ListTile(
        leading: Icon(Icons.web_outlined),
        title: Text('网页版关闭标签页后监控会停止'),
        subtitle: Text('隐藏标签页可能被限速；持续监控优先使用桌面端'),
      );
    }
    final bg = AppBackground.instance;
    final subtitle = bg.supportsTray
        ? '关闭窗口后缩到托盘继续监控，从托盘图标恢复或退出'
        : bg.supportsForegroundService
        ? '监控时申请前台服务；省电策略和系统时限仍可能中断监控'
        : '系统限制，请保持应用在前台';
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('后台运行'),
          subtitle: Text(subtitle),
          value: ref.watch(runInBackgroundProvider),
          onChanged: bg.supportsTray || bg.supportsForegroundService
              ? (v) => ref.read(runInBackgroundProvider.notifier).set(v)
              : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bedtime_off_outlined),
          title: const Text('监控时阻止休眠'),
          value: ref.watch(keepAwakeProvider),
          onChanged: (v) => ref.read(keepAwakeProvider.notifier).set(v),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('清除课程缓存'),
          onTap: () async {
            await ref.read(courseCacheProvider).clear();
            if (context.mounted) showToast(context, '已清除', success: true);
          },
        ),
      ],
    );
  }
}

class _DiagnosticsEntry extends StatelessWidget {
  const _DiagnosticsEntry();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.network_check),
      title: const Text('连接诊断'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage())),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Captcha-recognition settings: built-in on-device model vs a custom OCR API.
class _OcrSettings extends ConsumerWidget {
  const _OcrSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(ocrApiProvider);
    final usingApi = api != null && api.isValid;
    return ListTile(
      leading: const Icon(Icons.auto_awesome),
      title: const Text('识别方式'),
      subtitle: Text(usingApi ? '自定义 API：${api.url}' : '内置离线模型'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showAdaptiveSheet<void>(
        context,
        scrollControlled: true,
        maxWidth: 560,
        builder: (_) => const _OcrApiEditor(),
      ),
    );
  }
}

class _OcrApiEditor extends ConsumerStatefulWidget {
  const _OcrApiEditor();
  @override
  ConsumerState<_OcrApiEditor> createState() => _OcrApiEditorState();
}

class _OcrApiEditorState extends ConsumerState<_OcrApiEditor> {
  late final TextEditingController _url;
  late final TextEditingController _imageField;
  late final TextEditingController _responseField;
  OcrRequestFormat _req = OcrRequestFormat.base64Json;
  OcrResponseFormat _resp = OcrResponseFormat.jsonField;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(ocrApiProvider);
    _url = TextEditingController(text: cfg?.url ?? '');
    _imageField = TextEditingController(text: cfg?.imageField ?? 'image');
    _responseField = TextEditingController(
      text: cfg?.responseField ?? 'result',
    );
    if (cfg != null) {
      _req = cfg.requestFormat;
      _resp = cfg.responseFormat;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _imageField.dispose();
    _responseField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('自定义 OCR API', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '留空即使用内置模型。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: 'https://127.0.0.1:8000/ocr',
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: '图片发送方式'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<OcrRequestFormat>(
                  value: _req,
                  isExpanded: true,
                  onChanged: (v) => setState(() => _req = v ?? _req),
                  items: const [
                    DropdownMenuItem(
                      value: OcrRequestFormat.base64Json,
                      child: Text('JSON 内 base64'),
                    ),
                    DropdownMenuItem(
                      value: OcrRequestFormat.multipart,
                      child: Text('multipart 文件上传'),
                    ),
                    DropdownMenuItem(
                      value: OcrRequestFormat.rawBytes,
                      child: Text('原始字节'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_req != OcrRequestFormat.rawBytes)
              TextField(
                controller: _imageField,
                decoration: const InputDecoration(
                  labelText: '图片字段名',
                  hintText: 'image',
                ),
              ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: '返回解析方式'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<OcrResponseFormat>(
                  value: _resp,
                  isExpanded: true,
                  onChanged: (v) => setState(() => _resp = v ?? _resp),
                  items: const [
                    DropdownMenuItem(
                      value: OcrResponseFormat.jsonField,
                      child: Text('JSON 字段'),
                    ),
                    DropdownMenuItem(
                      value: OcrResponseFormat.plainText,
                      child: Text('纯文本'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_resp == OcrResponseFormat.jsonField)
              TextField(
                controller: _responseField,
                decoration: const InputDecoration(
                  labelText: '结果字段名',
                  hintText: 'result',
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await ref.read(ocrApiProvider.notifier).set(null);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('用内置模型'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final url = _url.text.trim();
                      final prev = ref.read(ocrApiProvider);
                      final cfg = url.isEmpty
                          ? null
                          : OcrApiConfig(
                              url: url,
                              requestFormat: _req,
                              imageField: _imageField.text.trim().isEmpty
                                  ? 'image'
                                  : _imageField.text.trim(),
                              responseFormat: _resp,
                              responseField: _responseField.text.trim().isEmpty
                                  ? 'result'
                                  : _responseField.text.trim(),
                              headers: prev?.headers ?? const {},
                            );
                      if (cfg != null && !cfg.isValid) {
                        showToast(
                          context,
                          '请输入以 http:// 或 https:// 开头的完整接口地址',
                          success: false,
                        );
                        return;
                      }
                      await ref.read(ocrApiProvider.notifier).set(cfg);
                      if (context.mounted) {
                        showToast(
                          context,
                          cfg == null ? '已改用内置模型' : '已保存',
                          success: true,
                        );
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonitorSettings extends ConsumerWidget {
  const _MonitorSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(monitorConfigProvider);
    final ctrl = ref.read(monitorConfigProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final baseSecs = cfg.basePollInterval.inMilliseconds / 1000.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Icon(Icons.speed),
              const SizedBox(width: 12),
              const Expanded(child: Text('检查间隔')),
              Text(
                '${baseSecs.toStringAsFixed(1)} 秒',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: baseSecs.clamp(1.0, 15.0),
          min: 1,
          max: 15,
          divisions: 28,
          label: '${baseSecs.toStringAsFixed(1)}s',
          onChanged: (v) => ctrl.update(
            cfg.copyWith(
              basePollInterval: Duration(milliseconds: (v * 1000).round()),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '越短越快，但越容易触发学校服务器的频率限制，建议 2 到 4 秒。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          secondary: const Icon(Icons.rocket_launch_outlined),
          title: const Text('抢开模式'),
          subtitle: const Text('开放瞬间服务器繁忙或报错时退避重试而不是停止'),
          value: cfg.rushMode,
          onChanged: (v) => ctrl.update(cfg.copyWith(rushMode: v)),
        ),
      ],
    );
  }
}

class _BrowserNotificationSetting extends StatefulWidget {
  const _BrowserNotificationSetting();

  @override
  State<_BrowserNotificationSetting> createState() =>
      _BrowserNotificationSettingState();
}

class _BrowserNotificationSettingState
    extends State<_BrowserNotificationSetting> {
  late String _permission;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _permission = NotificationService.instance.browserPermission;
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    final granted = _permission == 'granted';
    final denied = _permission == 'denied';
    return ListTile(
      leading: Icon(
        granted
            ? Icons.notifications_active_outlined
            : Icons.notifications_outlined,
      ),
      title: const Text('浏览器通知'),
      subtitle: Text(
        granted
            ? '已启用'
            : denied
            ? '浏览器已拒绝，请在站点权限中允许后刷新'
            : '网页在后台时也能收到抢课结果',
      ),
      trailing: granted
          ? const Icon(Icons.check_circle_outline)
          : FilledButton.tonal(
              onPressed: denied || _requesting ? null : _request,
              child: Text(_requesting ? '请求中' : '启用'),
            ),
    );
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    await NotificationService.instance.requestPermission();
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _permission = NotificationService.instance.browserPermission;
    });
  }
}

class ServerOriginSetting extends ConsumerStatefulWidget {
  const ServerOriginSetting({super.key, this.compact = false, this.onSaved});

  final bool compact;
  final Future<void> Function()? onSaved;

  @override
  ConsumerState<ServerOriginSetting> createState() =>
      _ServerOriginSettingState();
}

class _ServerOriginSettingState extends ConsumerState<ServerOriginSetting> {
  late final TextEditingController _ctrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(storageProvider).origin());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = Storage.originLockedByBuild;
    return Padding(
      padding: EdgeInsets.all(widget.compact ? 0 : 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.dns_outlined),
              SizedBox(width: 12),
              Text('选课服务器', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            locked ? '调试构建已固定服务器地址。' : '更改后所有账号需要重新登录。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            enabled: !locked && !_saving,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '地址',
              hintText: Storage.defaultOrigin,
              errorText: _error,
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: locked || _saving
                    ? null
                    : () => setState(() {
                        _ctrl.text = Storage.defaultOrigin;
                        _error = null;
                      }),
                child: const Text('默认'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: locked || _saving ? null : _save,
                child: Text(_saving ? '保存中' : '保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    var origin = _ctrl.text.trim();
    while (origin.endsWith('/')) {
      origin = origin.substring(0, origin.length - 1);
    }
    final uri = Uri.tryParse(origin);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() => _error = '请输入完整的 http:// 或 https:// 地址');
      return;
    }

    final signedIn = ref.read(signedInAccountsProvider);
    if (signedIn.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('切换服务器'),
          content: const Text('当前登录的账号都会退出。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出并切换'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(storageProvider).setOrigin(origin);
      for (final id in [...signedIn]) {
        await leaveAccount(ref, id);
      }
      ref.invalidate(anonymousAuthProvider);
      ref.invalidate(publicInfoServiceProvider);
      await widget.onSaved?.call();
      if (mounted) showToast(context, '已切换服务器', success: true);
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
