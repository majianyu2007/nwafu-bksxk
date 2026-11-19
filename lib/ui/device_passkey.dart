/// "Fingerprint / Face ID sign-in": binds this app as a passkey device on the
/// unified identity, with the dialogs the personal centre's re-check needs.
library;


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../app/providers.dart' show storageProvider;
import '../core/errors.dart';

String defaultDeviceName() {
  if (kIsWeb) return '西农教务助手';
  final os = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'iPhone',
    TargetPlatform.android => 'Android',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.windows => 'Windows',
    _ => '设备',
  };
  return '西农教务助手 · $os';
}

/// Runs the whole binding: confirm with biometrics, re-check (captcha),
/// register. Returns true when bound. [password] is the unified password the
/// user just typed or saved; asked for when null.
Future<bool> bindThisDeviceFlow(
  BuildContext context,
  WidgetRef ref, {
  String? password,
}) async {
  final unlock = ref.read(deviceUnlockProvider);
  final session = ref.read(eduSessionProvider.notifier);
  final account = ref.read(eduSessionProvider).account;
  if (account == null) return false;
  if (!await unlock.available()) {
    if (context.mounted) {
      _snack(context, '此设备不支持指纹、面容或设备密码验证');
    }
    return false;
  }
  final label = await unlock.label();
  if (!context.mounted) return false;
  final name = await _askDeviceName(context, label);
  if (name == null || !context.mounted) return false;
  password ??= await ref.read(storageProvider).eduPassword(account.username);
  if (!context.mounted) return false;
  password ??= await _askPassword(context);
  if (password == null || !context.mounted) return false;
  if (!await unlock.confirm('验证$label')) return false;
  if (!context.mounted) return false;
  try {
    await _withProgress(
      context,
      session.bindThisDevice(
        deviceName: name,
        password: password,
        solveCaptcha: (image) => _askCaptcha(context, image),
      ),
    );
    if (context.mounted) _snack(context, '已开启$label登录');
    return true;
  } catch (e) {
    if (context.mounted) {
      _snack(
        context,
        e is AppError ? '绑定失败：${e.message}' : '绑定失败，请稍后重试',
      );
    }
    return false;
  }
}

Future<T> _withProgress<T>(BuildContext context, Future<T> work) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('正在绑定本设备…')),
          ],
        ),
      ),
    ),
  );
  nav.push(route);
  try {
    return await work;
  } finally {
    if (route.isActive) nav.removeRoute(route);
  }
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

Future<String?> _askDeviceName(BuildContext context, String label) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        icon: Icon(unlockIcon(label)),
        title: '开启$label登录',
        header: Text(
          '会在学校统一身份认证里添加一台“生物识别”设备。'
          '密钥只存在这台设备上，每次登录都要验证$label。'
          '可在设置或学校个人中心解绑。',
        ),
        labelText: '设备名称',
        initialText: defaultDeviceName(),
        maxLength: 30,
        confirmLabel: '继续',
        trimResult: true,
      ),
    );

Future<String?> _askPassword(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _TextPromptDialog(
    title: '确认统一身份认证密码',
    labelText: '密码',
    obscureText: true,
    autofocus: true,
    confirmLabel: '确定',
    trimResult: false,
  ),
);

Future<String?> _askCaptcha(BuildContext context, Uint8List image) {
  if (!context.mounted) return Future<String?>.value();
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: '学校要求安全校验',
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('输入图中的字符'),
          if (image.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(image, height: 48, gaplessPlayback: true),
            ),
          ],
        ],
      ),
      labelText: '验证码',
      autofocus: true,
      confirmLabel: '确定',
      trimResult: true,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.labelText,
    required this.confirmLabel,
    this.icon,
    this.header,
    this.initialText = '',
    this.obscureText = false,
    this.autofocus = false,
    this.maxLength,
    this.trimResult = true,
  });

  final Widget? icon;
  final String title;
  final Widget? header;
  final String labelText;
  final String initialText;
  final bool obscureText;
  final bool autofocus;
  final int? maxLength;
  final String confirmLabel;
  final bool trimResult;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = widget.trimResult ? _ctrl.text.trim() : _ctrl.text;
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: widget.icon,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _ctrl,
            obscureText: widget.obscureText,
            autofocus: widget.autofocus,
            maxLength: widget.maxLength,
            decoration: InputDecoration(labelText: widget.labelText),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
