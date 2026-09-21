import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/update_providers.dart';
import '../core/update_links.dart';
import '../core/web_env.dart';
import '../data/update_service.dart';

Future<void> _openUpdateLink(BuildContext context, Uri uri) async {
  if (!isOfficialUpdateLink(uri)) return;
  try {
    if (await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    )) {
      return;
    }
  } catch (_) {
    // Platform launchers may be unavailable; keep the URL accessible to copy.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: const Text('无法打开浏览器，可复制官方链接后手动访问。'),
    action: SnackBarAction(
      label: '复制链接',
      onPressed: () => Clipboard.setData(ClipboardData(text: uri.toString())),
    ),
  ));
}

/// A non-modal notice. Watching it also initializes the throttled startup
/// check; it never refreshes the app, changes accounts or touches monitoring.
class UpdateNoticeBanner extends ConsumerWidget {
  const UpdateNoticeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updatesProvider);
    if (!state.showNotice) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update_alt,
                      color: scheme.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      [
                        if (state.app.hasUpdate)
                          '应用 ${state.app.release!.version} 可更新',
                        if (state.bridge.hasUpdate)
                          '桥接脚本 ${state.bridge.release!.version} 可更新',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: '暂不提醒',
                    onPressed: ref.read(updatesProvider.notifier).dismissNotice,
                    icon: const Icon(Icons.close),
                    color: scheme.onSecondaryContainer,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (state.app.hasUpdate)
                    TextButton.icon(
                      onPressed: () =>
                          _openUpdateLink(context, state.app.release!.url),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(isWebRuntime ? '在新标签页打开' : '查看应用更新'),
                    ),
                  if (state.bridge.hasUpdate)
                    TextButton.icon(
                      onPressed: () =>
                          _openUpdateLink(context, bridgeInstallerUri),
                      icon: const Icon(Icons.extension_outlined, size: 18),
                      label: const Text('打开脚本安装页'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Embedded inside the existing Settings group card.
class UpdateSettings extends ConsumerWidget {
  const UpdateSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updatesProvider);
    final version = state.version;
    final versionLabel = state.loadingVersion
        ? '读取版本中…'
        : version == null
            ? '版本读取失败'
            : state.buildNumber.isEmpty
                ? version
                : '$version (${state.buildNumber})';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('西农本科选课 $versionLabel'),
          subtitle: const Text(
            '每天最多自动检查一次；仅提示，不会自动安装、刷新页面或中断监控。',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: state.checking
                    ? null
                    : () => ref.read(updatesProvider.notifier).checkNow(),
                icon: state.checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(state.checking ? '正在检查…' : '检查更新'),
              ),
              TextButton.icon(
                onPressed: () => _openUpdateLink(context, appReleasesUri),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('官方发布页'),
              ),
            ],
          ),
        ),
        _UpdateResult(
          title: '应用更新',
          check: state.app,
          fallback: isWebRuntime ? webAppUri : appReleasesUri,
          action: isWebRuntime ? '在新标签页打开网页版' : '查看更新与下载',
        ),
        const Divider(height: 1),
        if (isWebRuntime)
          _UpdateResult(
            title: 'Web 桥接脚本',
            check: state.bridge,
            fallback: bridgeInstallerUri,
            action: '打开脚本安装页',
            installedLabel: !isWebBridgeReady
                ? '未检测到已安装脚本'
                : installedWebBridgeVersion == null
                    ? '已检测到脚本，版本未知'
                    : '已安装 ${installedWebBridgeVersion!}',
          )
        else
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('Web 桥接脚本'),
            subtitle: const Text('原生应用不需要此脚本；仅在浏览器使用网页版时安装。'),
            onTap: () => _openUpdateLink(context, bridgeInstallerUri),
            trailing: const Icon(Icons.open_in_new),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Text(
            '更新检查只访问官方 GitHub / 发布站点，不发送账号、密码或选课会话。'
            '安装脚本后请自行选择合适时机刷新网页版。',
          ),
        ),
      ],
    );
  }
}

class _UpdateResult extends StatelessWidget {
  const _UpdateResult({
    required this.title,
    required this.check,
    required this.fallback,
    required this.action,
    this.installedLabel,
  });

  final String title;
  final UpdateCheck check;
  final Uri fallback;
  final String action;
  final String? installedLabel;

  @override
  Widget build(BuildContext context) {
    final release = check.release;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (installedLabel != null) ...[
            const SizedBox(height: 4),
            Text(installedLabel!),
          ],
          const SizedBox(height: 4),
          Text(check.message),
          if (release != null) ...[
            const SizedBox(height: 4),
            Text(
              '发布版本：${release.version}'
              '${release.publishedAt == null ? '' : ' · ${release.publishedAt!.toLocal().toIso8601String().substring(0, 10)}'}',
            ),
            if (release.name.isNotEmpty) Text(release.name),
          ],
          if (release != null && release.notes.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('更新说明'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(release.notes),
                ),
              ],
            ),
          TextButton.icon(
            onPressed: () => _openUpdateLink(context, release?.url ?? fallback),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(action),
          ),
        ],
      ),
    );
  }
}
