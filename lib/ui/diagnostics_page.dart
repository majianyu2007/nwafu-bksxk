/// Diagnostics: connectivity probe, online users, session state, version,
/// and a scrubbed report the user can copy.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/constants.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import 'layout.dart';
import 'widgets.dart';

/// Runs a reachability probe against the configured origin.
final reachabilityProvider =
    FutureProvider.autoDispose<ReachabilityResult>((ref) async {
  final origin = ref.watch(storageProvider).origin();
  return ApiClient(origin: origin).probe();
});

/// The current online user count, from the same public endpoint the official
/// login page shows it from.
final onlineUsersProvider = FutureProvider.autoDispose<OnlineUserStats>(
    (ref) => ref.watch(publicInfoServiceProvider).fetchOnlineUsers());

class DiagnosticsPage extends ConsumerWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final probe = ref.watch(reachabilityProvider);
    final session = ref.watch(sessionProvider);
    final origin = ref.watch(storageProvider).origin();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('连接诊断'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(reachabilityProvider);
              ref.invalidate(onlineUsersProvider);
            },
            tooltip: '重新检测',
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final side = ((constraints.maxWidth - kReadableMaxWidth) / 2)
            .clamp(16.0, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 16, side, 16),
          children: [
            _Tile(title: '选课服务器', value: origin, icon: Icons.dns_outlined),
            const SizedBox(height: 12),
            probe.when(
              loading: () => const Card(
                child: ListTile(
                  leading: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  title: Text('正在检测'),
                ),
              ),
              error: (e, _) => _ResultCard(
                  ok: false, title: '检测失败', detail: '$e', hint: null),
              data: (r) => _ResultCard(
                ok: r.reachable,
                title: r.reachable ? '连接正常' : '无法连接',
                detail: r.latency != null
                    ? '${r.detail}，延迟 ${r.latency!.inMilliseconds} ms'
                    : r.detail,
                hint: r.error?.hint,
              ),
            ),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('选课系统只在校园网内可用，校外请先连接学校 VPN。'),
              ),
            ),
            const SizedBox(height: 20),
            ref.watch(onlineUsersProvider).when(
                  loading: () => const _Tile(
                      title: '在线人数', value: '查询中', icon: Icons.people_outline),
                  error: (e, _) => _Tile(
                      title: '在线人数', value: '$e', icon: Icons.people_outline),
                  data: (stats) => _Tile(
                    title: '在线人数',
                    value: stats.count > 0 ? '${stats.count} 人' : '无数据',
                    icon: Icons.people_outline,
                  ),
                ),
            const SizedBox(height: 20),
            Text('会话',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _Tile(
                title: '登录状态',
                value: switch (session.phase) {
                  AuthPhase.loggedIn => '已登录',
                  AuthPhase.loggingIn => '登录中',
                  AuthPhase.loggedOut => '未登录',
                  AuthPhase.expired => '登录已失效',
                },
                icon: Icons.verified_user_outlined),
            _Tile(
                title: '学号',
                value: session.student?.studentCode ?? '—',
                icon: Icons.badge_outlined),
            _Tile(
                title: '轮次',
                value: session.activeBatch?.name ?? '—',
                icon: Icons.event_outlined),
            const _Tile(
                title: '客户端版本', value: kAppVersion, icon: Icons.info_outline),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => _copyReport(context, ref, origin, session, probe),
              icon: const Icon(Icons.copy_all),
              label: const Text('复制诊断信息'),
            ),
          ],
        );
      }),
    );
  }

  void _copyReport(
    BuildContext context,
    WidgetRef ref,
    String origin,
    SessionState session,
    AsyncValue<ReachabilityResult> probe,
  ) {
    final reach = probe.asData?.value;
    final stats = ref.read(onlineUsersProvider).asData?.value;
    // Scrub: no password, no token, no cookies; student code masked.
    final code = session.student?.studentCode ?? '';
    final maskedCode = code.length > 4
        ? '${code.substring(0, 2)}****${code.substring(code.length - 2)}'
        : '****';
    final report = StringBuffer()
      ..writeln('# 西农本科选课 诊断报告')
      ..writeln('client: $kAppVersion')
      ..writeln('origin: $origin')
      ..writeln('reachable: ${reach?.reachable ?? 'unknown'}')
      ..writeln('detail: ${reach?.detail ?? '—'}')
      ..writeln('latency_ms: ${reach?.latency?.inMilliseconds ?? '—'}')
      ..writeln('errorKind: ${reach?.error?.kind.name ?? '—'}')
      ..writeln('phase: ${session.phase.name}')
      ..writeln('studentCode(masked): $maskedCode')
      ..writeln('online_users: ${stats?.count ?? '—'}')
      ..writeln('batch: ${session.activeBatch?.name ?? '—'}');
    Clipboard.setData(ClipboardData(text: report.toString()));
    showToast(context, '已复制', success: true);
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(
      {required this.ok,
      required this.title,
      required this.detail,
      required this.hint});
  final bool ok;
  final String title;
  final String detail;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ok ? Colors.green : scheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.check_circle : Icons.error, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          TextStyle(fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 4),
                  Text(detail),
                  if (hint != null) ...[
                    const SizedBox(height: 6),
                    Text(hint!,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }
}
