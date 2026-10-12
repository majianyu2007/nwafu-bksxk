/// Settings rows for the unified account: this device's fingerprint / Face
/// ID sign-in and off-campus access through the embedded VPN.
library;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/campus_access.dart';
import '../app/edu_providers.dart';
import '../app/providers.dart';
import '../data/vpn/campus_route.dart';
import 'device_passkey.dart';

class DeviceSignInSetting extends ConsumerStatefulWidget {
  const DeviceSignInSetting({super.key});

  @override
  ConsumerState<DeviceSignInSetting> createState() =>
      _DeviceSignInSettingState();
}

class _DeviceSignInSettingState extends ConsumerState<DeviceSignInSetting> {
  bool? _bound;
  bool _supported = false;
  String _label = '指纹/面容';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final account = ref.read(eduSessionProvider).account;
    final unlock = ref.read(deviceUnlockProvider);
    final supported = await unlock.available();
    final label = supported ? await unlock.label() : _label;
    final bound = account == null
        ? false
        : await ref
              .read(eduSessionProvider.notifier)
              .hasDeviceKey(account.username);
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _label = label;
      _bound = bound;
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作未完成，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(eduSessionProvider).signedIn;
    if (!signedIn) return const SizedBox.shrink();
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: Text('$_label登录'),
      subtitle: Text(
        !_supported
            ? '此设备不支持'
            : _bound == true
            ? '已开启'
            : '不用输密码和短信验证码',
      ),
      value: _bound == true,
      onChanged: !_supported || _busy || _bound == null ? null : _toggle,
    );
  }
}

class CampusAccessSetting extends ConsumerWidget {
  const CampusAccessSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(campusAccessProvider);
    final c = ref.read(campusAccessProvider.notifier);
    final storage = ref.watch(storageProvider);
    ref.listen(campusAccessProvider, (prev, next) {
      if (next.pending != null && prev?.pending != next.pending) {
        showVpnStepDialog(context, ref);
      }
    });
    final (icon, text) = switch (s.route) {
      CampusRoute.direct => (Icons.lan_outlined, '校园网直连'),
      CampusRoute.vpn => (Icons.vpn_lock_outlined, '校外访问（VPN）'),
      CampusRoute.unreachable => (Icons.cloud_off_outlined, '连不上学校服务器'),
      CampusRoute.unknown => (Icons.travel_explore_outlined, '尚未检测'),
    };
    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(text),
          subtitle: Text(
            s.message ??
                '在校外时自动通过学校 VPN 连接，账号密码与统一身份认证相同',
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
          value: storage.campusVpnAuto(),
          onChanged: c.vpnAvailable
              ? (v) async {
                  await storage.setCampusVpnAuto(v);
                  ref.invalidate(storageProvider);
                }
              : null,
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
  final value = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(pending.needs == 'sms' ? '校外访问短信验证' : '校外访问动态码'),
      content: TextField(
        controller: code,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: pending.hint ?? '验证码'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, code.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  if (value == null || value.trim().isEmpty) {
    await c.disconnect();
  } else {
    await c.answer(value.trim());
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

  @override
  void initState() {
    super.initState();
    decodeImageFromList(widget.image).then((img) {
      if (mounted) {
        setState(
          () => _natural = Size(img.width.toDouble(), img.height.toDouble()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final natural = _natural;
    return AlertDialog(
      title: const Text('校外访问安全验证'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.hint ?? '按顺序点击图中的文字'),
          const SizedBox(height: 12),
          if (natural == null)
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
                            child: CircleAvatar(
                              radius: 12,
                              child: Text('${i + 1}'),
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
      actions: [
        TextButton(
          onPressed: _points.isEmpty
              ? null
              : () => setState(_points.clear),
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
