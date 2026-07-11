/// Diagnostics: connectivity probe, session state, app version, and a scrubbed
/// activity/error log the user can copy for troubleshooting.
///
/// This is the "no bare 请求失败" backstop — it tells the user exactly what the
/// client can and cannot reach, and why.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/api_client.dart';
import 'widgets.dart';

/// Runs a reachability probe against the configured origin.
final reachabilityProvider = FutureProvider.autoDispose<ReachabilityResult>((ref) async {
  final client = ref.watch(apiClientProvider);
  return client.probe();
});

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
            onPressed: () => ref.invalidate(reachabilityProvider),
            tooltip: '重新检测',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Tile(
            title: '选课服务器',
            value: origin,
            icon: Icons.dns_outlined,
          ),
          const SizedBox(height: 12),
          probe.when(
            loading: () => const Card(
              child: ListTile(
                leading: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                title: Text('正在检测连接…'),
              ),
            ),
            error: (e, _) => _ResultCard(
              ok: false,
              title: '检测失败',
              detail: '$e',
              hint: null,
            ),
            data: (r) => _ResultCard(
              ok: r.reachable,
              title: r.reachable ? '连接正常' : '无法连接',
              detail: r.latency != null
                  ? '${r.detail} · 延迟 ${r.latency!.inMilliseconds}ms'
                  : r.detail,
              hint: r.error?.hint,
            ),
          ),
          const SizedBox(height: 20),
          Text('校园网提示',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bullet('本系统仅在校园网环境内可用。'),
                  _Bullet('校外请先连接学校 VPN 接入校园网，再打开本应用。'),
                  _Bullet('若在校园网内仍无法连接，可能是当前不在选课时段或服务器维护。'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('会话',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _Tile(title: '登录状态', value: switch (session.phase) {
            AuthPhase.loggedIn => '已登录',
            AuthPhase.loggingIn => '登录中',
            AuthPhase.loggedOut => '未登录',
          }, icon: Icons.verified_user_outlined),
          _Tile(title: '当前学号', value: session.student?.studentCode ?? '—', icon: Icons.badge_outlined),
          _Tile(title: '当前轮次', value: session.activeBatch?.name ?? '—', icon: Icons.event_outlined),
          const _Tile(title: '客户端版本', value: '1.0.0', icon: Icons.info_outline),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: () => _copyReport(context, ref, origin, session, probe),
            icon: const Icon(Icons.copy_all),
            label: const Text('复制诊断信息（已脱敏）'),
          ),
        ],
      ),
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
    // Scrub: no password, no token, no cookies; student code masked.
    final code = session.student?.studentCode ?? '';
    final maskedCode = code.length > 4 ? '${code.substring(0, 2)}****${code.substring(code.length - 2)}' : '****';
    final report = StringBuffer()
      ..writeln('# 西农本科选课 诊断报告')
      ..writeln('client: 1.0.0')
      ..writeln('origin: $origin')
      ..writeln('reachable: ${reach?.reachable ?? 'unknown'}')
      ..writeln('detail: ${reach?.detail ?? '—'}')
      ..writeln('latency_ms: ${reach?.latency?.inMilliseconds ?? '—'}')
      ..writeln('errorKind: ${reach?.error?.kind.name ?? '—'}')
      ..writeln('phase: ${session.phase.name}')
      ..writeln('studentCode(masked): $maskedCode')
      ..writeln('batch: ${session.activeBatch?.name ?? '—'}');
    Clipboard.setData(ClipboardData(text: report.toString()));
    showToast(context, '诊断信息已复制到剪贴板', success: true);
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.ok, required this.title, required this.detail, required this.hint});
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
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 4),
                  Text(detail),
                  if (hint != null) ...[
                    const SizedBox(height: 6),
                    Text(hint!, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
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

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('·  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
