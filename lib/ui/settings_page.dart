/// Settings: appearance, monitor cadence, captcha recognition, accounts,
/// server, notifications, diagnostics.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../core/constants.dart';
import '../data/background.dart';
import '../data/http_ocr_solver.dart';
import '../data/notifications.dart';
import '../data/storage.dart';
import 'diagnostics_page.dart';
import 'layout.dart';
import 'login_page.dart';
import 'widgets.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ((constraints.maxWidth - kReadableMaxWidth) / 2)
            .clamp(16.0, double.infinity);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, 12, side, 32),
          children: [
            Text('设置',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            const _Group(title: '外观', children: [_Appearance()]),
            const _Group(title: '监控', children: [_MonitorSettings()]),
            const _Group(title: '验证码', children: [_OcrSettings()]),
            const _Group(title: '账号', children: [_Accounts()]),
            const _Group(title: '后台运行', children: [_BackgroundSettings()]),
            const _Group(
              title: '高级',
              children: [
                ServerOriginSetting(),
                _BrowserNotificationSetting(),
                _DiagnosticsEntry(),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('西农本科选课 $kAppVersion'),
                  subtitle: Text('只连接所配置的选课服务器，密码用官网相同的方式加密后发送。'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Appearance extends ConsumerWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final ctrl = ref.read(themeControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final custom = !theme.useDynamic &&
        !kSeedPresets.any((p) => p.$2.toARGB32() == theme.seed.toARGB32());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('显示模式'),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('系统')),
              ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
              ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
            ],
            selected: {theme.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => ctrl.setMode(s.first),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          title: const Text('跟随系统强调色'),
          value: theme.useDynamic,
          onChanged: ctrl.setUseDynamic,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Opacity(
            opacity: theme.useDynamic ? 0.4 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题色',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (name, c) in kSeedPresets)
                      _Swatch(
                        color: c,
                        tooltip: name,
                        selected: !theme.useDynamic &&
                            theme.seed.toARGB32() == c.toARGB32(),
                        onTap: () => ctrl.setSeed(c),
                      ),
                    _Swatch(
                      color: custom ? theme.seed : null,
                      tooltip: '自定义',
                      selected: custom,
                      onTap: () => _pickCustom(context, ref, theme.seed),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCustom(
      BuildContext context, WidgetRef ref, Color initial) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _HuePickerDialog(initial: initial),
    );
    if (picked != null) {
      await ref.read(themeControllerProvider.notifier).setSeed(picked);
    }
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.color,
      required this.tooltip,
      required this.selected,
      required this.onTap});
  final Color? color;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: color,
            gradient: color == null
                ? const SweepGradient(colors: [
                    Colors.red,
                    Colors.yellow,
                    Colors.green,
                    Colors.cyan,
                    Colors.blue,
                    Colors.purple,
                    Colors.red,
                  ])
                : null,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : color == null
                  ? const Icon(Icons.add, color: Colors.white, size: 18)
                  : null,
        ),
      ),
    );
  }
}

/// Hue / saturation / lightness sliders with a live preview.
class _HuePickerDialog extends StatefulWidget {
  const _HuePickerDialog({required this.initial});
  final Color initial;

  @override
  State<_HuePickerDialog> createState() => _HuePickerDialogState();
}

class _HuePickerDialogState extends State<_HuePickerDialog> {
  late HSLColor _hsl = HSLColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsl.toColor();
    final scheme = ColorScheme.fromSeed(
        seedColor: color, brightness: Theme.of(context).brightness);
    Widget slider(String label, double value, double max,
        ValueChanged<double> onChanged) {
      return Row(
        children: [
          SizedBox(width: 40, child: Text(label)),
          Expanded(
            child: Slider(value: value, max: max, onChanged: onChanged),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('自定义主题色'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: TextStyle(
                    color: scheme.onPrimary, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            slider('色相', _hsl.hue, 360,
                (v) => setState(() => _hsl = _hsl.withHue(v))),
            slider('饱和度', _hsl.saturation, 1,
                (v) => setState(() => _hsl = _hsl.withSaturation(v))),
            slider('明度', _hsl.lightness, 1,
                (v) => setState(() => _hsl = _hsl.withLightness(v))),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, color),
            child: const Text('使用')),
      ],
    );
  }
}

/// Signed-in accounts (switch / sign out), saved accounts (forget), add.
class _Accounts extends ConsumerWidget {
  const _Accounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(signedInAccountsProvider);
    final activeId = ref.watch(activeAccountIdProvider);
    final saved = ref.watch(accountsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in signedIn)
          Builder(builder: (context) {
            final s = ref.watch(sessionControllerProvider(id));
            final expired = s.phase == AuthPhase.expired;
            return ListTile(
              leading: Icon(
                id == activeId
                    ? Icons.account_circle
                    : Icons.account_circle_outlined,
                color: expired ? scheme.error : null,
              ),
              title: Text(s.displayName),
              subtitle: Text([
                id,
                if (s.activeBatch != null) s.activeBatch!.name,
                if (expired) '登录已失效',
              ].join('  ')),
              trailing: TextButton(
                onPressed: () => _signOut(context, ref, id, s.displayName),
                child: const Text('退出'),
              ),
              onTap: id == activeId
                  ? null
                  : () => ref.read(activeAccountIdProvider.notifier).state = id,
            );
          }),
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
        const _SilentReloginSetting(),
        SwitchListTile(
          secondary: const Icon(Icons.tab_outlined),
          title: const Text('多账号'),
          subtitle: const Text('同时登录多个账号，以标签页切换，各自监控'),
          value: ref.watch(multiAccountProvider),
          onChanged: (v) => ref.read(multiAccountProvider.notifier).set(v),
        ),
        if (ref.watch(multiAccountProvider))
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const LoginPage(addingAccount: true),
              )),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('添加账号'),
            ),
          ),
      ],
    );
  }

  Future<void> _signOut(
      BuildContext context, WidgetRef ref, String id, String name) async {
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
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('退出')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await leaveAccount(ref, id);
  }
}

/// How hard the app tries to recover a dropped session on its own before
/// asking the user (each attempt = one captcha fetch + OCR + login).
class _SilentReloginSetting extends ConsumerStatefulWidget {
  const _SilentReloginSetting();

  @override
  ConsumerState<_SilentReloginSetting> createState() =>
      _SilentReloginSettingState();
}

class _SilentReloginSettingState extends ConsumerState<_SilentReloginSetting> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final v = ref.read(silentReloginAttemptsProvider);
    _ctrl = TextEditingController(text: v < 0 ? '' : '$v');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply(String text) async {
    final n = int.tryParse(text.trim());
    if (n == null || n < 0) return;
    await ref.read(silentReloginAttemptsProvider.notifier).set(n.clamp(0, 999));
  }

  @override
  Widget build(BuildContext context) {
    final attempts = ref.watch(silentReloginAttemptsProvider);
    final enabled = ref.watch(silentReloginEnabledProvider);
    final guard = ref.watch(contestedGuardProvider);
    final guardMinutes = ref.watch(contestedWindowMinutesProvider);
    final unlimited = attempts < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.autorenew),
          title: const Text('掉线后自动重新登录'),
          subtitle: Text(!enabled
              ? '关闭，掉线后直接弹窗'
              : unlimited
                  ? '不限次数，间隔逐步拉长'
                  : '验证码最多识别 $attempts 次，仍失败再弹窗并说明原因'),
          value: enabled,
          onChanged: (v) => ref.read(silentReloginEnabledProvider.notifier).set(v),
        ),
        if (enabled) Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _ctrl,
                  enabled: !unlimited,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '次数',
                    isDense: true,
                  ),
                  onSubmitted: _apply,
                  onTapOutside: (_) => _apply(_ctrl.text),
                ),
              ),
              const SizedBox(width: 16),
              FilterChip(
                label: const Text('不限'),
                selected: unlimited,
                onSelected: (v) {
                  if (v) {
                    ref.read(silentReloginAttemptsProvider.notifier).set(-1);
                  } else {
                    _ctrl.text = '3';
                    ref.read(silentReloginAttemptsProvider.notifier).set(3);
                  }
                },
              ),
            ],
          ),
        ),
        if (enabled)
          SwitchListTile(
            secondary: const Icon(Icons.swap_horiz),
            title: const Text('被踢下线时让步'),
            subtitle: Text(guard
                ? '重新登录后 $guardMinutes 分钟内再次被踢就不再抢回会话，改为弹窗'
                : '关闭：每次被踢都自动重新登录，把别处的会话踢掉'),
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
                    value: guardMinutes.toDouble().clamp(1, 30),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '$guardMinutes 分钟',
                    onChanged: (v) => ref
                        .read(contestedWindowMinutesProvider.notifier)
                        .set(v.round()),
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

/// Keep-alive switches; the platform decides what each one means.
class _BackgroundSettings extends ConsumerWidget {
  const _BackgroundSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return const ListTile(
        leading: Icon(Icons.web_outlined),
        title: Text('网页版关闭标签页后监控会停止'),
        subtitle: Text('需要后台监控请使用桌面或手机应用'),
      );
    }
    final bg = AppBackground.instance;
    final subtitle = bg.supportsTray
        ? '关闭窗口后缩到托盘继续监控，从托盘图标恢复或退出'
        : bg.supportsForegroundService
            ? '监控运行时显示常驻通知，系统不会清理后台'
            : '系统限制，请保持应用在前台';
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.visibility_off_outlined),
          title: const Text('后台运行'),
          subtitle: Text(subtitle),
          value: ref.watch(runInBackgroundProvider),
          onChanged: (v) => ref.read(runInBackgroundProvider.notifier).set(v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bedtime_off_outlined),
          title: const Text('监控时阻止休眠'),
          value: ref.watch(keepAwakeProvider),
          onChanged: (v) => ref.read(keepAwakeProvider.notifier).set(v),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('清除课程缓存'),
          onTap: () async {
            await ref.read(courseCacheProvider).clear();
            if (context.mounted) showToast(context, '已清除', success: true);
          },
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

/// Captcha-recognition settings: built-in on-device model vs a custom OCR API.
class _OcrSettings extends ConsumerWidget {
  const _OcrSettings();

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

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(ocrApiProvider);
    _url = TextEditingController(text: cfg?.url ?? '');
    _imageField = TextEditingController(text: cfg?.imageField ?? 'image');
    _responseField =
        TextEditingController(text: cfg?.responseField ?? 'result');
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
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('自定义 OCR API', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('留空即使用内置模型。',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                  labelText: '接口地址', hintText: 'https://127.0.0.1:8000/ocr'),
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
                    DropdownMenuItem(
                        value: OcrRequestFormat.base64Json,
                        child: Text('JSON 内 base64')),
                    DropdownMenuItem(
                        value: OcrRequestFormat.multipart,
                        child: Text('multipart 文件上传')),
                    DropdownMenuItem(
                        value: OcrRequestFormat.rawBytes,
                        child: Text('原始字节')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_req != OcrRequestFormat.rawBytes)
              TextField(
                controller: _imageField,
                decoration: const InputDecoration(
                    labelText: '图片字段名', hintText: 'image'),
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
                    DropdownMenuItem(
                        value: OcrResponseFormat.jsonField,
                        child: Text('JSON 字段')),
                    DropdownMenuItem(
                        value: OcrResponseFormat.plainText, child: Text('纯文本')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_resp == OcrResponseFormat.jsonField)
              TextField(
                controller: _responseField,
                decoration: const InputDecoration(
                    labelText: '结果字段名', hintText: 'result'),
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
                    child: const Text('用内置模型'),
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
                              imageField: _imageField.text.trim().isEmpty
                                  ? 'image'
                                  : _imageField.text.trim(),
                              responseFormat: _resp,
                              responseField: _responseField.text.trim().isEmpty
                                  ? 'result'
                                  : _responseField.text.trim(),
                            );
                      await ref.read(ocrApiProvider.notifier).set(cfg);
                      if (context.mounted) {
                        showToast(context, cfg == null ? '已改用内置模型' : '已保存',
                            success: true);
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
              const Expanded(child: Text('检查间隔')),
              Text('${baseSecs.toStringAsFixed(1)} 秒',
                  style: TextStyle(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
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

class _BrowserNotificationSetting extends StatefulWidget {
  const _BrowserNotificationSetting();

  @override
  State<_BrowserNotificationSetting> createState() =>
      _BrowserNotificationSettingState();
}

class _BrowserNotificationSettingState
    extends State<_BrowserNotificationSetting> {
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
    return ListTile(
      leading: Icon(granted
          ? Icons.notifications_active_outlined
          : Icons.notifications_outlined),
      title: const Text('浏览器通知'),
      subtitle: Text(
        granted
            ? '已启用'
            : denied
                ? '浏览器已拒绝，请在站点权限中允许后刷新'
                : '网页在后台时也能收到抢课结果',
      ),
      trailing: granted
          ? const Icon(Icons.check_circle_outline)
          : FilledButton.tonal(
              onPressed: denied || _requesting ? null : _request,
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
      for (final id in [...signedIn]) {
        await leaveAccount(ref, id);
      }
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
