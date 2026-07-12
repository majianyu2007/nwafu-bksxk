/// Settings: appearance (theme mode + accent), monitor cadence, server origin,
/// accounts, and logout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../data/http_ocr_solver.dart';
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
        const _Group(
          title: '验证码识别',
          children: [
            _OcrSettings(),
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

/// Captcha-recognition settings: built-in on-device model vs a custom OCR API.
class _OcrSettings extends ConsumerWidget {
  const _OcrSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(ocrApiProvider);
    final usingApi = api != null && api.isValid;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('识别方式'),
          subtitle: Text(usingApi
              ? '使用自定义 OCR API：${api.url}'
              : '使用内置离线模型（自动识别并填写验证码，识别失败自动换一张重试）'),
          isThreeLine: true,
        ),
        ListTile(
          leading: const Icon(Icons.api),
          title: const Text('自定义 OCR API'),
          subtitle: Text(usingApi ? '已配置' : '可选：填入你自己的打码服务地址'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => const _OcrApiEditor(),
          ),
        ),
      ],
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
    _responseField = TextEditingController(text: cfg?.responseField ?? 'result');
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
        left: 20, right: 20, top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('自定义 OCR API', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('留空并保存即恢复使用内置离线模型。',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: '接口地址', hintText: 'https://127.0.0.1:8000/ocr'),
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
                    DropdownMenuItem(value: OcrRequestFormat.base64Json, child: Text('JSON 内 base64')),
                    DropdownMenuItem(value: OcrRequestFormat.multipart, child: Text('multipart 文件上传')),
                    DropdownMenuItem(value: OcrRequestFormat.rawBytes, child: Text('原始字节 body')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_req != OcrRequestFormat.rawBytes)
              TextField(
                controller: _imageField,
                decoration: const InputDecoration(labelText: '图片字段名', hintText: 'image'),
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
                    DropdownMenuItem(value: OcrResponseFormat.jsonField, child: Text('JSON 字段')),
                    DropdownMenuItem(value: OcrResponseFormat.plainText, child: Text('纯文本')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_resp == OcrResponseFormat.jsonField)
              TextField(
                controller: _responseField,
                decoration: const InputDecoration(labelText: '结果字段名', hintText: 'result'),
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
                    child: const Text('恢复内置模型'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final url = _url.text.trim();
                      final cfg = url.isEmpty
                          ? null
                          : OcrApiConfig(
                              url: url,
                              requestFormat: _req,
                              imageField: _imageField.text.trim().isEmpty ? 'image' : _imageField.text.trim(),
                              responseFormat: _resp,
                              responseField: _responseField.text.trim().isEmpty ? 'result' : _responseField.text.trim(),
                            );
                      await ref.read(ocrApiProvider.notifier).set(cfg);
                      if (context.mounted) {
                        showToast(context, cfg == null ? '已恢复内置模型' : '已保存 OCR API', success: true);
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
              const Expanded(child: Text('检查余量间隔')),
              Text('${baseSecs.toStringAsFixed(1)} 秒',
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Slider(
          value: baseSecs.clamp(1.0, 15.0),
          min: 1,
          max: 15,
          divisions: 28,
          label: '${baseSecs.toStringAsFixed(1)}s',
          onChanged: (v) => ctrl.update(cfg.copyWith(
            basePollInterval: Duration(milliseconds: (v * 1000).round()),
          )),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '间隔越短抢课越快，但也更接近学校服务器的频率限制。建议 2–4 秒；抢开模式下会自动提速。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          secondary: const Icon(Icons.rocket_launch_outlined),
          title: const Text('抢开模式'),
          subtitle: const Text('选课开放瞬间服务器常因人多而崩溃/繁忙。开启后，遇到 5xx、超时或“系统繁忙”视为临时过载，自动退避重试直到成功，而不是停止。账号或验证码错误仍会停止。'),
          isThreeLine: true,
          value: cfg.rushMode,
          onChanged: (v) => ctrl.update(cfg.copyWith(rushMode: v)),
        ),
        const ListTile(
          leading: Icon(Icons.verified),
          title: Text('结果确认与自动保护'),
          subtitle: Text('提交后读取服务器最终回执才算成功；正常模式下遇到验证码、账号异常、系统维护或限流会立即停止，不会重复提交同一空位。'),
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
