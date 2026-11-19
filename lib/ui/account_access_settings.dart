/// Settings rows for the unified account: this device's fingerprint / Face
/// ID sign-in and off-campus access through the embedded VPN.
library;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/campus_access.dart';
import '../app/edu_providers.dart';
import '../app/providers.dart';
import '../core/errors.dart';
import '../data/vpn/campus_route.dart';
import 'device_passkey.dart';
import 'widgets.dart';

class DeviceSignInSetting extends ConsumerStatefulWidget {
  const DeviceSignInSetting({super.key});

  @override
  ConsumerState<DeviceSignInSetting> createState() =>
      _DeviceSignInSettingState();
}

class _DeviceSignInSettingState extends ConsumerState<DeviceSignInSetting> {
  bool _supported = false;
  String _label = '指纹/面容';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final unlock = ref.read(deviceUnlockProvider);
    final supported = await unlock.available();
    final label = supported ? await unlock.label() : _label;
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _label = label;
    });
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        await bindThisDeviceFlow(context, ref);
      } else {
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('关闭$_label登录？'),
            content: const Text('会从学校统一身份认证里删除这台设备。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await ref.read(eduSessionProvider.notifier).unbindThisDevice();
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e is AppError ? e.message : '操作未完成，请稍后重试';
        showToast(context, msg, success: false);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(eduSessionProvider).signedIn;
    if (!signedIn) return const SizedBox.shrink();
    final bound = ref.watch(deviceKeyBoundProvider).value;
    return SwitchListTile(
      secondary: Icon(unlockIcon(_label)),
      title: Text('$_label登录'),
      subtitle: Text(
        !_supported
            ? '此设备不支持'
            : bound == true
            ? '已开启'
            : '不用输密码和短信验证码',
      ),
      value: bound == true,
      onChanged: !_supported || _busy || bound == null ? null : _toggle,
    );
  }
}

class CampusAccessSetting extends ConsumerWidget {
  const CampusAccessSetting({super.key});

  Future<void> _editTotp(BuildContext context, WidgetRef ref) async {
    final account = ref.read(eduSessionProvider).account;
    if (account == null) {
      showToast(context, '请先登录统一身份认证', success: false);
      return;
    }
    final storage = ref.read(storageProvider);
    final existing = await storage.campusVpnTotp(account.username) ?? '';
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: existing);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('校外 VPN 动态码密钥（TOTP）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '填入安全令牌的 Base32 密钥后，校外自动连接 VPN 时会自动生成动态码，免弹窗秒连。留空保存可清除。',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'TOTP Secret',
                  hintText: '例如 JBSWY3DPEHPK3PXP',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (result == null) return;
      await storage.setCampusVpnTotp(
        account.username,
        result.isEmpty ? null : result.replaceAll(RegExp(r'\s+'), ''),
      );
      if (context.mounted) {
        showToast(
          context,
          result.isEmpty ? '已清除动态码密钥' : '已保存，校外连接将自动填充动态码',
          success: true,
        );
      }
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(campusAccessProvider);
    final c = ref.read(campusAccessProvider.notifier);
    final autoVpn = ref.watch(campusAutoVpnProvider);
    final signedIn = ref.watch(eduSessionProvider).signedIn;
    ref.listen(campusAccessProvider, (prev, next) {
      if (next.pending != null && prev?.pending != next.pending) {
        showVpnStepDialog(context, ref);
      }
    });
    final (icon, text) = switch (s.route) {
      CampusRoute.direct => (Icons.lan_outlined, '选课系统可直连'),
      CampusRoute.vpn => (Icons.vpn_lock_outlined, '校外访问（VPN）'),
      CampusRoute.unreachable => (Icons.cloud_off_outlined, '选课系统连不上（需校园网）'),
      CampusRoute.unknown => (Icons.travel_explore_outlined, '尚未检测'),
    };
    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(text),
          subtitle: Text(
            s.message ??
                '只有选课系统需要校园网；在校外时自动通过学校 VPN 连接选课系统，账号密码与统一身份认证相同',
          ),
          trailing: s.busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : s.route == CampusRoute.vpn
              ? TextButton(onPressed: c.disconnect, child: const Text('断开'))
              : TextButton(
                  onPressed: () => c.check(userInitiated: true),
                  child: const Text('检测'),
                ),
        ),
        SwitchListTile(
          title: const Text('校外自动连接'),
          subtitle: Text(
            c.vpnAvailable ? '连不上学校服务器时自动连接' : '此版本不支持',
          ),
          value: autoVpn,
          onChanged: c.vpnAvailable
              ? (v) => ref.read(campusAutoVpnProvider.notifier).set(v)
              : null,
        ),
        if (c.vpnAvailable && signedIn)
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('VPN 动态码自动填充'),
            subtitle: const Text('配置 TOTP 密钥，校外连接免输动态码'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editTotp(context, ref),
          ),
      ],
    );
  }
}

/// Shows the gateway's pending step: a click-the-characters captcha, or an
/// SMS / authenticator code.
Future<void> showVpnStepDialog(BuildContext context, WidgetRef ref) async {
  final c = ref.read(campusAccessProvider.notifier);
  final pending = ref.read(campusAccessProvider).pending;
  if (pending == null) return;
  if (pending.needs == 'captcha') {
    final image = c.pendingImage;
    if (image == null) return;
    final coords = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ClickCaptchaDialog(image: image, hint: pending.hint),
    );
    if (coords == null) {
      await c.disconnect();
    } else {
      await c.answer(coords);
    }
    return;
  }
  final code = TextEditingController();
  try {
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: code,
        builder: (context, text, _) {
          final canSubmit = text.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(pending.needs == 'sms' ? '校外访问短信验证' : '校外访问动态码'),
            content: TextField(
              controller: code,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: pending.hint ?? '验证码'),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(context, v);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(context, code.text)
                    : null,
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (value == null || value.trim().isEmpty) {
      await c.disconnect();
    } else {
      await c.answer(value.trim());
    }
  } finally {
    code.dispose();
  }
}

class _ClickCaptchaDialog extends StatefulWidget {
  const _ClickCaptchaDialog({required this.image, this.hint});
  final Uint8List image;
  final String? hint;

  @override
  State<_ClickCaptchaDialog> createState() => _ClickCaptchaDialogState();
}

class _ClickCaptchaDialogState extends State<_ClickCaptchaDialog> {
  final _points = <Offset>[];
  Size? _natural;
  bool _decodeFailed = false;

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.image).then(
      (img) {
        final size = Size(img.width.toDouble(), img.height.toDouble());
        img.dispose();
        if (mounted) {
          setState(() {
            if (size.width > 0 && size.height > 0) {
              _natural = size;
            } else {
              _decodeFailed = true;
            }
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _decodeFailed = true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final natural = _natural;
    return AlertDialog(
      title: const Text('校外访问安全验证'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.hint ?? '按顺序点击图中的文字（点序号可撤销）'),
            const SizedBox(height: 12),
            if (_decodeFailed)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('验证码图片加载失败，请取消后重试'),
              )
            else if (natural == null)
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth.clamp(0.0, natural.width * 1.5);
                  final scale = w / natural.width;
                  return GestureDetector(
                    onTapUp: (d) =>
                        setState(() => _points.add(d.localPosition / scale)),
                    child: SizedBox(
                      width: w,
                      height: natural.height * scale,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.memory(widget.image, fit: BoxFit.fill),
                          ),
                          for (var i = 0; i < _points.length; i++)
                            Positioned(
                              left: _points[i].dx * scale - 12,
                              top: _points[i].dy * scale - 12,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _points.removeAt(i)),
                                child: CircleAvatar(
                                  radius: 12,
                                  child: Text('${i + 1}'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _points.isEmpty ? null : () => setState(_points.clear),
          child: const Text('重选'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _points.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  '[${_points.map((p) => '[${p.dx.round()},${p.dy.round()}]').join(',')}]',
                ),
          child: const Text('提交'),
        ),
      ],
    );
  }
}
