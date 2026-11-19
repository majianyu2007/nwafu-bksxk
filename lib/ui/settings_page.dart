/// Settings: appearance, monitor cadence, captcha recognition, accounts,
/// server, notifications, diagnostics.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_access_settings.dart';
import 'layout.dart';
import 'settings/account_system_settings.dart';
import 'settings/appearance_settings.dart';
import 'settings/selection_settings.dart';
import 'settings/timetable_reminder_settings.dart';
import 'sync_settings.dart';
import 'update_widgets.dart';
import 'widgets/glass.dart';

export 'settings/account_system_settings.dart' show ServerOriginSetting;

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

const _categories = <_SettingsCategory>[
  _SettingsCategory(
    id: '账号与安全',
    title: '账号与安全',
    subtitle: kIsWeb ? '教务会话、选课账号' : '统一身份认证、通行密钥、校外访问、选课账号',
    icon: Icons.shield_outlined,
    children: [
      EduSettings(),
      if (!kIsWeb) DeviceSignInSetting(),
      if (!kIsWeb) CampusAccessSetting(),
      AccountsSettings(),
    ],
  ),
  _SettingsCategory(
    id: '课表与提醒',
    title: '课表与提醒',
    subtitle: kIsWeb ? '视图密度、课程显示、导出 .ics' : '视图密度、课前提醒、后台同步与日历',
    icon: Icons.calendar_month_outlined,
    children: [
      TimetableDisplaySettings(),
      if (!kIsWeb) ReminderSettings(),
      SyncSettings(),
    ],
  ),
  _SettingsCategory(
    id: '外观',
    title: '外观与缩放',
    subtitle: '深浅主题、界面缩放、文字大小、玻璃效果',
    icon: Icons.palette_outlined,
    children: [AppearanceSettings()],
  ),
  _SettingsCategory(
    id: '选课与抢课',
    title: '选课与抢课',
    subtitle: '监控间隔、自动重登、验证码识别、缓存',
    icon: Icons.bolt_outlined,
    children: [
      MonitorSettings(),
      SilentReloginSettings(),
      OcrSettings(),
      ClearCourseCacheTile(),
    ],
  ),
  _SettingsCategory(
    id: '后台与通知',
    title: kIsWeb ? '通知' : '后台与保活',
    subtitle: kIsWeb ? '浏览器桌面通知' : '关闭最小化到托盘、防休眠、前台服务',
    icon: Icons.notifications_active_outlined,
    children: [
      if (!kIsWeb) BackgroundSettings(),
      if (kIsWeb) BrowserNotificationSetting(),
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
      DiagnosticsEntry(),
    ],
  ),
];

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

  @override
  void initState() {
    super.initState();
    final target = widget.section;
    final idx = target == null
        ? 0
        : _categories.indexWhere((c) => c.id == target || c.title == target);
    _selectedIndex = idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _categories[_selectedIndex.clamp(0, _categories.length - 1)];
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
                          itemCount: _categories.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 48,
                            endIndent: 12,
                          ),
                          itemBuilder: (context, i) {
                            final c = _categories[i];
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
                      for (var i = 0; i < _categories.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Icon(
                            _categories[i].icon,
                            color: scheme.primary,
                          ),
                          title: Text(_categories[i].title),
                          subtitle: Text(
                            _categories[i].subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _SettingsCategoryScreen(
                                category: _categories[i],
                              ),
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
