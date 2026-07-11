/// Settings: appearance (theme mode + accent), monitor cadence, server origin,
/// accounts, and logout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import 'diagnostics_page.dart';
import 'widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final themeCtrl = ref.read(themeControllerProvider.notifier);
    final session = ref.watch(sessionProvider);
    final accounts = ref.watch(accountsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text('设置', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),

        _Group(
          title: '外观',
          children: [
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('显示模式'),
              subtitle: Text(switch (theme.mode) {
                ThemeMode.system => '跟随系统',
                ThemeMode.light => '浅色',
                ThemeMode.dark => '深色',
              }),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
                ],
                selected: {theme.mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => themeCtrl.setMode(s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题色', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    children: [
                      for (final c in kSeedPresets)
                        GestureDetector(
                          onTap: () => themeCtrl.setSeed(c),
                          child: Container(
                            height: 36,
                            width: 36,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.seed.toARGB32() == c.toARGB32()
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: theme.seed.toARGB32() == c.toARGB32()
                                ? const Icon(Icons.check, color: Colors.white, size: 18)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const _Group(
          title: '抢课设置',
          children: [
            _MonitorSettings(),
          ],
        ),

        _Group(
          title: '账号',
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(session.student?.name ?? '未登录'),
              subtitle: Text(session.student?.studentCode ?? ''),
            ),
            for (final a in accounts)
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(a.displayName),
                subtitle: Text(a.loginName),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref.read(accountsProvider.notifier).remove(a.id),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(sessionProvider.notifier).logout();
                },
                icon: const Icon(Icons.logout),
                label: const Text('退出登录'),
              ),
            ),
          ],
        ),

        const _Group(
          title: '高级',
          children: [
            _OriginSetting(),
            _DiagnosticsEntry(),
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('关于'),
              subtitle: Text('西农本科选课 · 选课/抢课快人一步。仅连接 bksxk.nwafu.edu.cn，登录密码使用与官网一致的 DES 加密。'),
              isThreeLine: true,
            ),
          ],
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
      subtitle: const Text('检测能否连到选课服务器、查看会话状态、导出脱敏日志'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()),
      ),
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
            child: Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    )),
          ),
          Card(child: Column(children: children)),
        ],
      ),
    );
  }
}

class _MonitorSettings extends ConsumerWidget {
  const _MonitorSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The engine config is fixed at construction; expose the effective cadence
    // as guidance. Fine-grained tuning could rebuild the engine — kept simple
    // here to avoid disrupting active watches.
    return const Column(
      children: [
        ListTile(
          leading: Icon(Icons.speed),
          title: Text('轮询节奏'),
          subtitle: Text('普通课程约每 3 秒检查一次余量，优先课程更快（不低于约 1 秒）。发现空位立即以预构建的选课结构体提交，出错时自动退避，避免高频轰炸学校服务器。'),
          isThreeLine: true,
        ),
        ListTile(
          leading: Icon(Icons.verified),
          title: Text('结果确认与自动保护'),
          subtitle: Text('提交后读取服务器最终回执才算成功；遇到验证码、账号异常、系统维护或限流会立即停止，不会重复提交同一空位。'),
          isThreeLine: true,
        ),
      ],
    );
  }
}

class _OriginSetting extends ConsumerStatefulWidget {
  const _OriginSetting();
  @override
  ConsumerState<_OriginSetting> createState() => _OriginSettingState();
}

class _OriginSettingState extends ConsumerState<_OriginSetting> {
  late final TextEditingController _ctrl;

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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.dns_outlined),
              SizedBox(width: 12),
              Text('服务器地址'),
            ],
          ),          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(hintText: 'https://bksxk.nwafu.edu.cn'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () async {
                final origin = _ctrl.text.trim();
                await ref.read(storageProvider).setOrigin(origin);
                ref.read(apiClientProvider).origin = origin;
                if (context.mounted) showToast(context, '已保存服务器地址', success: true);
              },
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}
