/// Course selection monitor, silent re-login, and captcha OCR settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/http_ocr_solver.dart';
import '../layout.dart';
import '../widgets.dart';

class MonitorSettings extends ConsumerStatefulWidget {
  const MonitorSettings({super.key});

  @override
  ConsumerState<MonitorSettings> createState() => _MonitorSettingsState();
}

class _MonitorSettingsState extends ConsumerState<MonitorSettings> {
  double? _draftSecs;

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(monitorConfigProvider);
    final ctrl = ref.read(monitorConfigProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final persistedSecs = cfg.basePollInterval.inMilliseconds / 1000.0;
    final displaySecs = (_draftSecs ?? persistedSecs).clamp(1.0, 15.0);

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
                '${displaySecs.toStringAsFixed(1)} 秒',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: displaySecs,
          min: 1,
          max: 15,
          divisions: 28,
          label: '${displaySecs.toStringAsFixed(1)}s',
          onChanged: (v) => setState(() => _draftSecs = v),
          onChangeEnd: (v) {
            setState(() => _draftSecs = null);
            ctrl.update(
              cfg.copyWith(
                basePollInterval: Duration(milliseconds: (v * 1000).round()),
              ),
            );
          },
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

/// How hard the app tries to recover a dropped session on its own before
/// asking the user (each attempt = one captcha fetch + OCR + login).
class SilentReloginSettings extends ConsumerStatefulWidget {
  const SilentReloginSettings({super.key});

  @override
  ConsumerState<SilentReloginSettings> createState() =>
      _SilentReloginSettingsState();
}

class _SilentReloginSettingsState extends ConsumerState<SilentReloginSettings> {
  int? _draftGuardMinutes;

  @override
  Widget build(BuildContext context) {
    final attempts = ref.watch(silentReloginAttemptsProvider);
    final enabled = ref.watch(silentReloginEnabledProvider);
    final guard = ref.watch(contestedGuardProvider);
    final persistedMinutes = ref.watch(contestedWindowMinutesProvider);
    final guardMinutes = (_draftGuardMinutes ?? persistedMinutes).clamp(1, 30);
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
                    value: guardMinutes.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '$guardMinutes 分钟',
                    onChanged: (v) =>
                        setState(() => _draftGuardMinutes = v.round()),
                    onChangeEnd: (v) {
                      final mins = v.round();
                      setState(() => _draftGuardMinutes = null);
                      ref
                          .read(contestedWindowMinutesProvider.notifier)
                          .set(mins);
                    },
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

/// Captcha-recognition settings: built-in on-device model vs a custom OCR API.
class OcrSettings extends ConsumerWidget {
  const OcrSettings({super.key});

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
  bool _saving = false;

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

  Future<void> _useBuiltIn() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(ocrApiProvider.notifier).set(null);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
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
      showToast(context, '请输入以 http:// 或 https:// 开头的完整接口地址', success: false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(ocrApiProvider.notifier).set(cfg);
      if (mounted) {
        showToast(context, cfg == null ? '已改用内置模型' : '已保存', success: true);
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
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
              enabled: !_saving,
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
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _req = v ?? _req),
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
                enabled: !_saving,
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
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _resp = v ?? _resp),
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
                enabled: !_saving,
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
                    onPressed: _saving ? null : _useBuiltIn,
                    child: const Text('用内置模型'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存'),
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
