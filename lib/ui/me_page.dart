/// 我的: who is signed in, where each account stands, the tools that do not
/// have a tab of their own, and the way into 设置.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/campus_access.dart';
import '../app/edu_providers.dart';
import '../app/providers.dart';
import '../app/update_providers.dart';
import '../core/web_env.dart';
import '../data/vpn/campus_route.dart';
import 'edu_login_page.dart';
import '../app/portal_providers.dart';
import 'degree_page.dart';
import 'free_rooms_page.dart';
import 'library_page.dart';
import 'portal_inbox_page.dart';
import 'layout.dart';
import 'settings_page.dart';
import 'widgets/glass.dart';

/// A tool shown on 我的. Features add themselves to [meTools].
class MeTool {
  const MeTool({
    required this.icon,
    required this.label,
    required this.open,
    this.badge,
    this.nativeOnly = false,
  });
  final IconData icon;
  final String label;
  final Widget Function() open;

  /// A small count on the tile (unread messages, …).
  final ProviderListenable<int?>? badge;
  final bool nativeOnly;
}

/// The tools on 我的, in order.
final meTools = <MeTool>[
  MeTool(
    icon: Icons.school_outlined,
    label: '学业进度',
    open: () => const DegreePage(),
  ),
  MeTool(
    icon: Icons.mark_email_unread_outlined,
    label: '消息',
    open: () => const PortalInboxPage(),
    badge: portalBadgeProvider,
  ),
  MeTool(
    icon: Icons.local_library_outlined,
    label: '图书馆',
    open: () => const LibraryPage(),
  ),
  MeTool(
    icon: Icons.meeting_room_outlined,
    label: '空教室',
    open: () => const FreeRoomsPage(),
  ),
];

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    final settingsCard = GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            subtitle: const Text('账号、提醒、外观、选课'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于与更新'),
            subtitle: Text(version == null ? '西农教务助手' : '西农教务助手 $version'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(section: '版本与更新'),
              ),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final wide = w >= 840;
        final maxW = wide ? 1120.0 : kReadableMaxWidth;
        final gutter = pageGutter(w);
        final side = ((w - maxW) / 2).clamp(gutter, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 12, side, 120),
          children: [
            Text(
              '我的',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (wide)
              TwoColumn(
                breakpoint: 800,
                primaryFlex: 5,
                secondaryFlex: 5,
                primary: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileCard(),
                    SizedBox(height: 16),
                    _ToolGrid(),
                  ],
                ),
                secondary: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    settingsCard,
                    const SizedBox(height: 16),
                    GlassCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: const Text('外观与界面缩放'),
                        subtitle: const Text('主题色、玻璃效果、自动/紧凑/宽松缩放'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(section: '外观'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              const _ProfileCard(),
              const SizedBox(height: 16),
              const _ToolGrid(),
              const SizedBox(height: 16),
              settingsCard,
            ],
          ],
        );
      },
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(eduSessionProvider);
    final account = session.account;
    final selection = ref.watch(signedInAccountsProvider);
    final route = ref.watch(campusAccessProvider).route;
    final bound = ref.watch(deviceKeyBoundProvider).value ?? false;
    final unlock = ref.watch(unlockKindProvider).value;

    if (!session.signedIn || account == null) {
      return GlassCard(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const EduLoginPage())),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.person_outline, color: scheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('登录统一身份认证', style: theme.textTheme.titleMedium),
                  Text('一个账号：课表、成绩、选课、校外访问', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      );
    }
    final name = account.name.isEmpty ? account.username : account.name;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  name.characters.first,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        account.username,
                        account.major,
                        account.className,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _StatusChip(
                icon: Icons.verified_user,
                label: '统一认证',
                ok: true,
              ),
              _StatusChip(
                icon: Icons.checklist,
                label: selection.isEmpty ? '选课未登录' : '选课已登录',
                ok: selection.isNotEmpty,
              ),
              if (kIsWeb)
                _StatusChip(
                  icon: Icons.extension_outlined,
                  label: isFullCampusBridgeReady
                      ? '桥接 ${installedWebBridgeVersion ?? ''} 已就绪'.trim()
                      : isWebBridgeReady
                      ? '桥接脚本可更新'
                      : '未检测到桥接脚本',
                  ok: isFullCampusBridgeReady,
                )
              else ...[
                _StatusChip(
                  icon: unlock?.icon ?? Icons.fingerprint,
                  label: '${unlock?.label ?? '快捷'}登录${bound ? '已开' : '未开'}',
                  ok: bound,
                ),
                if (route != CampusRoute.unknown)
                  _StatusChip(
                    icon: route == CampusRoute.vpn
                        ? Icons.vpn_lock_outlined
                        : Icons.lan_outlined,
                    label: switch (route) {
                      CampusRoute.direct => '选课可直连',
                      CampusRoute.vpn => '选课走 VPN',
                      CampusRoute.unreachable => '选课需校园网',
                      CampusRoute.unknown => '',
                    },
                    ok: route == CampusRoute.direct || route == CampusRoute.vpn,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.ok,
  });
  final IconData icon;
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ok ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12.5, color: color)),
        ],
      ),
    );
  }
}

class _ToolGrid extends ConsumerWidget {
  const _ToolGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tools = [
      for (final t in meTools)
        if (!t.nativeOnly || !kIsWeb) t,
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final columns = (c.maxWidth / 92).floor().clamp(3, 6);
          return Wrap(
            children: [
              for (final t in tools)
                SizedBox(
                  width: c.maxWidth / columns,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => t.open())),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          Badge(
                            isLabelVisible:
                                t.badge != null &&
                                (ref.watch(t.badge!) ?? 0) > 0,
                            label: t.badge == null
                                ? null
                                : Text('${ref.watch(t.badge!) ?? 0}'),
                            child: Icon(
                              t.icon,
                              size: 28,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(t.label, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
