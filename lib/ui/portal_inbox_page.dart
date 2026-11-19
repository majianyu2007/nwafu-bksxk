/// 消息: what is waiting in the school portals: unread messages and to-dos
/// from 一网通办, and the ehall notices. Tapping an item opens it in the
/// browser, since acting on most of them needs the school's own pages.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/edu_providers.dart';
import '../app/portal_providers.dart';
import '../core/errors.dart';
import '../core/web_env.dart';
import '../data/portal_service.dart';
import 'edu_login_page.dart';
import 'layout.dart';
import 'widgets/glass.dart';

/// Opens [uri] outside the app; offers to copy it when no browser opens.
Future<void> openPortalLink(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Fall through to the copy offer.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('打不开浏览器，可以复制链接自己打开。'),
      action: SnackBarAction(
        label: '复制链接',
        onPressed: () => Clipboard.setData(ClipboardData(text: '$uri')),
      ),
    ),
  );
}

class PortalInboxPage extends ConsumerStatefulWidget {
  const PortalInboxPage({super.key});

  @override
  ConsumerState<PortalInboxPage> createState() => _PortalInboxPageState();
}

class _PortalInboxPageState extends ConsumerState<PortalInboxPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(eduSessionProvider).signedIn) {
        ref.read(portalProvider.notifier).refresh();
      }
    });
  }

  Future<void> _login() => Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => const EduLoginPage()));

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(eduSessionProvider.select((s) => s.signedIn));
    final state = ref.watch(portalProvider);
    final inbox = state.inbox;
    final theme = Theme.of(context);
    Future<void> refresh() => ref.read(portalProvider.notifier).refresh();
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('消息'),
          actions: [
            if (signedIn && kPortalSupported)
              IconButton(
                tooltip: '刷新',
                onPressed: state.loading ? null : refresh,
                icon: const Icon(Icons.refresh),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!kPortalSupported)
                        _Hint(
                          icon: Icons.extension_outlined,
                          text: '网页版查看学校消息需要 1.4.0 及以上版本的桥接脚本，更新后刷新页面即可。',
                          action: FilledButton.icon(
                            onPressed: openWebBridgeInstaller,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('更新桥接脚本 (1.4.0)'),
                          ),
                        )
                      else if (!signedIn)
                      _Hint(
                        icon: Icons.mail_outline,
                        text: '登录统一身份认证后，这里会显示一网通办的未读消息、待办和学校通知。',
                        action: FilledButton(
                          onPressed: _login,
                          child: const Text('去登录'),
                        ),
                      )
                    else ...[
                      if (state.loading) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                      ],
                      if (state.error != null) ...[
                        _ErrorNote(
                          error: state.error!,
                          onRetry: state.loading ? null : refresh,
                          onLogin: _login,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (inbox != null) ...[
                        _Counts(inbox: inbox),
                        const SizedBox(height: 20),
                        TwoColumn(
                          breakpoint: 840,
                          primaryFlex: 1,
                          secondaryFlex: 1,
                          primary: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Section(
                                title: '待办',
                                items: inbox.todos,
                                error: inbox.errors['todos'],
                                empty: (inbox.todo ?? 0) > 0
                                    ? '有 ${inbox.todo} 条待办，列表没取到，可以去一网通办看。'
                                    : '没有待办',
                                more: Uri.parse(
                                  '$kNewEhallOrigin/ywtb-portal/Lite/index.html',
                                ),
                              ),
                              _Section(
                                title: '消息',
                                items: inbox.messages,
                                error: inbox.errors['messages'],
                                empty: (inbox.unread ?? 0) > 0
                                    ? '有 ${inbox.unread} 条未读，列表没取到，可以去消息中心看。'
                                    : '没有消息',
                                more: Uri.parse(
                                  '$kNewEhallOrigin/new/portal/html/message/scenes_message_center.html',
                                ),
                              ),
                            ],
                          ),
                          secondary: _Section(
                            title: '通知公告',
                            items: inbox.notices,
                            error: inbox.errors['notices'],
                            empty: '暂时没有通知',
                            more: Uri.parse('$kEhallPortalOrigin/index.html'),
                          ),
                        ),
                        Text(
                          '消息只在打开本页时读取，不保存在本机上。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.inbox});
  final PortalInbox inbox;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int? n, IconData icon, {bool alert = false}) {
      final scheme = Theme.of(context).colorScheme;
      return Expanded(
        child: GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(
            children: [
              Icon(
                icon,
                color: alert && (n ?? 0) > 0 ? scheme.error : scheme.primary,
              ),
              const SizedBox(height: 6),
              Text(
                n == null ? '—' : '$n',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tile('未读消息', inbox.unread, Icons.mark_email_unread_outlined,
            alert: true),
        const SizedBox(width: 8),
        tile('待办', inbox.todo, Icons.pending_actions_outlined, alert: true),
        const SizedBox(width: 8),
        tile('已办', inbox.done, Icons.task_alt),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.empty,
    required this.more,
    this.error,
  });
  final String title;
  final List<PortalItem> items;
  final String empty;
  final Uri more;
  final AppError? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              TextButton(
                onPressed: () => openPortalLink(context, more),
                child: const Text('去官网'),
              ),
            ],
          ),
          if (error != null)
            Text(
              '没取到：${error!.message}',
              style: TextStyle(color: theme.colorScheme.error),
            )
          else if (items.isEmpty)
            Text(empty, style: TextStyle(color: theme.colorScheme.outline))
          else
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16),
                    _ItemTile(item: items[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});
  final PortalItem item;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (item.source.isNotEmpty) item.source,
      if (item.time.isNotEmpty) item.time,
    ].join(' · ');
    final url = item.url;
    return ListTile(
      leading: item.unread
          ? Icon(Icons.circle, size: 10, color: Theme.of(context).colorScheme.error)
          : null,
      minLeadingWidth: item.unread ? 10 : 0,
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.summary.isNotEmpty)
            Text(item.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (meta.isNotEmpty) Text(meta),
        ],
      ),
      trailing: url == null ? null : const Icon(Icons.open_in_new, size: 18),
      onTap: url == null ? null : () => openPortalLink(context, url),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({
    required this.error,
    required this.onRetry,
    required this.onLogin,
  });
  final AppError error;
  final VoidCallback? onRetry;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: scheme.onErrorContainer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error.message,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (error.hint != null) ...[
                const SizedBox(height: 6),
                Text(error.hint!),
              ],
              Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: onRetry, child: const Text('重试')),
                  if (error.kind == AppErrorKind.sessionExpired)
                    TextButton(onPressed: onLogin, child: const Text('重新登录')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry point for 我的: opens [PortalInboxPage], with the last known
/// unread + to-do count as a badge. Hidden on web and when signed out.
class PortalInboxTile extends ConsumerWidget {
  const PortalInboxTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kPortalSupported) return const SizedBox.shrink();
    final signedIn = ref.watch(eduSessionProvider.select((s) => s.signedIn));
    if (!signedIn) return const SizedBox.shrink();
    final badge = ref.watch(portalBadgeProvider);
    return ListTile(
      leading: Badge(
        isLabelVisible: (badge ?? 0) > 0,
        label: Text('${badge ?? 0}'),
        child: const Icon(Icons.mail_outline),
      ),
      title: const Text('消息'),
      subtitle: const Text('一网通办的未读消息、待办和学校通知'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PortalInboxPage()),
      ),
    );
  }
}
