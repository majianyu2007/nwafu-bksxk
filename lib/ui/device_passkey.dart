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
  var shown = true;
  showDialog<void>(
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
  ).whenComplete(() => shown = false);
  try {
    return await work;
  } finally {
    if (shown) nav.pop();
  }
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

Future<String?> _askDeviceName(BuildContext context, String label) {
  final c = TextEditingController(text: defaultDeviceName());
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.fingerprint),
      title: Text('开启$label登录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '会在学校统一身份认证里添加一台“生物识别”设备。'
            '密钥只存在这台设备上，每次登录都要验证$label。'
            '可在设置或学校个人中心解绑。',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: c,
            decoration: const InputDecoration(labelText: '设备名称'),
            maxLength: 30,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final v = c.text.trim();
            if (v.isNotEmpty) Navigator.pop(context, v);
          },
          child: const Text('继续'),
        ),
      ],
    ),
  );
}

Future<String?> _askPassword(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('确认统一身份认证密码'),
      content: TextField(
        controller: c,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: '密码'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<String?> _askCaptcha(BuildContext context, Uint8List image) {
  if (!context.mounted) return Future.value(null);
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('学校要求安全校验'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('输入图中的字符'),
          const SizedBox(height: 12),
          if (image.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(image, height: 48, gaplessPlayback: true),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: '验证码'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, c.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
