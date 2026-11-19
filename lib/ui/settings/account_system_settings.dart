/// Unified identity, multi-account, background keep-alive, browser
/// notifications, cache cleanup, diagnostics entry, and server origin settings.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edu_providers.dart';
import '../../app/providers.dart';
import '../../data/background.dart';
import '../../data/notifications.dart';
import '../../data/storage.dart';
import '../diagnostics_page.dart';
import '../edu_login_page.dart';
import '../login_page.dart';
import '../widgets.dart';

class EduSettings extends ConsumerWidget {
  const EduSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (signedIn, account) = ref.watch(
      eduSessionProvider.select((s) => (s.signedIn, s.account)),
    );
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(account?.displayName ?? '登录统一身份认证'),
          subtitle: Text(
            signedIn && account != null
                ? [
                    account.username,
                    account.major,
                  ].where((s) => s.isNotEmpty).join(' · ')
                : '登录后同步课表、成绩',
          ),
          trailing: signedIn
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
                    if (confirmed == true && context.mounted) {
                      await ref.read(eduSessionProvider.notifier).logout();
                    }
                  },
                  child: const Text('退出'),
                )
              : const Icon(Icons.chevron_right),
          onTap: signedIn ? null : () => pushEduLogin(context),
        ),
      ],
    );
  }
}

/// Signed-in accounts (switch / sign out), saved accounts (forget), add.
class AccountsSettings extends ConsumerWidget {
  const AccountsSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(signedInAccountsProvider);
    final activeId = ref.watch(activeAccountIdProvider);
    final saved = ref.watch(accountsProvider);
    final multiAccount = ref.watch(multiAccountProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in signedIn)
          Consumer(
            builder: (context, itemRef, _) {
              final s = itemRef.watch(sessionControllerProvider(id));
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
                  onPressed: () => _signOut(context, itemRef, id, s.displayName),
                  child: const Text('退出'),
                ),
                onTap: id == activeId
                    ? null
                    : () =>
                          itemRef.read(activeAccountIdProvider.notifier).state =
                              id,
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
          value: multiAccount,
          onChanged: (v) => ref.read(multiAccountProvider.notifier).set(v),
        ),
        if (multiAccount)
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
      if (ok != true || !context.mounted) return;
    }
    await leaveAccount(ref, id);
  }
}

/// Keep-alive switches; native only (web mounts [BrowserNotificationSetting]).
class BackgroundSettings extends ConsumerWidget {
  const BackgroundSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      ],
    );
  }
}

class ClearCourseCacheTile extends ConsumerWidget {
  const ClearCourseCacheTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.cleaning_services_outlined),
      title: const Text('清除课程缓存'),
      subtitle: const Text('清空本地保存的选课列表与全校课程缓存'),
      onTap: () async {
        await ref.read(courseCacheProvider).clear();
        if (context.mounted) showToast(context, '已清除', success: true);
      },
    );
  }
}

class BrowserNotificationSetting extends StatefulWidget {
  const BrowserNotificationSetting({super.key});

  @override
  State<BrowserNotificationSetting> createState() =>
      _BrowserNotificationSettingState();
}

class _BrowserNotificationSettingState
    extends State<BrowserNotificationSetting> {
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
    final unsupported = _permission == 'unsupported';
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
            : unsupported
            ? '当前浏览器不支持桌面通知'
            : denied
            ? '浏览器已拒绝，请在站点权限中允许后刷新'
            : '网页在后台时也能收到抢课结果',
      ),
      trailing: granted
          ? const Icon(Icons.check_circle_outline)
          : FilledButton.tonal(
              onPressed: denied || unsupported || _requesting ? null : _request,
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

class DiagnosticsEntry extends StatelessWidget {
  const DiagnosticsEntry({super.key});

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
      syncCustomCampusHost(origin);
      for (final id in [...signedIn]) {
        if (!mounted) return;
        await leaveAccount(ref, id);
      }
      if (!mounted) return;
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
