/// Off-campus access: picks direct vs the embedded VPN and keeps the shared
/// [CampusProxy] switch pointed at the running VPN.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/vpn/campus_proxy.dart';
import '../data/vpn/campus_route.dart';
import '../data/vpn/vpn_bridge.dart';
import 'edu_providers.dart';
import 'providers.dart';

class CampusAccessState {
  const CampusAccessState({
    this.route = CampusRoute.unknown,
    this.busy = false,
    this.message,
    this.pending,
  });
  final CampusRoute route;
  final bool busy;

  /// Last error or status line shown in Settings.
  final String? message;

  /// A gateway step waiting for the user (captcha / sms / totp).
  final VpnReply? pending;

  CampusAccessState copyWith({
    CampusRoute? route,
    bool? busy,
    String? message,
    VpnReply? pending,
    bool clearPending = false,
    bool clearMessage = false,
  }) => CampusAccessState(
    route: route ?? this.route,
    busy: busy ?? this.busy,
    message: clearMessage ? null : message ?? this.message,
    pending: clearPending ? null : pending ?? this.pending,
  );
}

final vpnBridgeProvider = Provider<VpnBridge>((ref) => createVpnBridge());

/// Dedicated setting provider for "校外自动连接", avoiding invalidation of
/// the root [storageProvider].
final campusAutoVpnProvider = StateNotifierProvider<BoolSetting, bool>((ref) {
  final s = ref.read(storageProvider);
  return BoolSetting(s.campusVpnAuto(), s.setCampusVpnAuto);
});

final campusAccessProvider =
    StateNotifierProvider<CampusAccessController, CampusAccessState>(
      (ref) => CampusAccessController(ref),
    );

class CampusAccessController extends StateNotifier<CampusAccessState> {
  CampusAccessController(this._ref, {DirectProbe? probe})
    : _probe = probe ?? defaultDirectProbe,
      _vpn = _ref.read(vpnBridgeProvider),
      super(const CampusAccessState());

  final Ref _ref;
  final DirectProbe _probe;
  final VpnBridge _vpn;
  Future<void>? _checking;
  int _opGen = 0;

  bool get vpnAvailable => !kIsWeb && _vpn.available;

  /// Re-evaluates the route; starts the VPN when off campus and allowed.
  Future<void> check({bool userInitiated = false}) =>
      _checking ??= _check(userInitiated).whenComplete(() => _checking = null);

  Future<void> _check(bool userInitiated) async {
    if (kIsWeb) return;
    final gen = ++_opGen;
    if (CampusProxy.instance.address != null) {
      final s = await _vpn.status();
      if (!mounted || gen != _opGen) return;
      if (s.running) {
        state = state.copyWith(route: CampusRoute.vpn, busy: false);
        return;
      }
      CampusProxy.instance.address = null;
    }
    state = state.copyWith(busy: true, clearMessage: true);
    if (await campusReachableDirectly(_probe)) {
      if (mounted && gen == _opGen) {
        state = state.copyWith(route: CampusRoute.direct, busy: false);
      }
      return;
    }
    if (!mounted || gen != _opGen) return;
    final auto = _ref.read(campusAutoVpnProvider);
    if (!vpnAvailable || (!auto && !userInitiated)) {
      state = state.copyWith(
        route: CampusRoute.unreachable,
        busy: false,
        message: vpnAvailable ? '选课系统只能在校园网访问' : '选课系统只能在校园网访问，此版本未内置校外访问',
      );
      return;
    }
    await connect();
  }

  /// Starts the VPN with the unified identity password.
  Future<void> connect() async {
    if (!vpnAvailable) {
      if (mounted) {
        state = state.copyWith(
          route: CampusRoute.unreachable,
          busy: false,
          message: '当前平台未内置校外访问',
        );
      }
      return;
    }
    final gen = ++_opGen;
    final account = _ref.read(eduSessionProvider).account;
    final storage = _ref.read(storageProvider);
    final password = account == null
        ? null
        : await storage.eduPassword(account.username);
    if (!mounted || gen != _opGen) return;
    if (account == null || password == null || password.isEmpty) {
      state = state.copyWith(
        route: CampusRoute.unreachable,
        busy: false,
        message: '校外访问需要已保存的统一身份认证密码（登录时勾选“记住密码”）',
      );
      return;
    }
    state = state.copyWith(busy: true, clearMessage: true, clearPending: true);
    try {
      final dir = await getApplicationSupportDirectory();
      final totp = await storage.campusVpnTotp(account.username) ?? '';
      if (!mounted || gen != _opGen) return;
      final reply = await _vpn.start(
        VpnConfig(
          username: account.username,
          password: password,
          totpSecret: totp,
          clientDataPath: '${dir.path}/vpn_client_${account.username}.json',
        ),
      );
      if (gen != _opGen) {
        if (reply.running) unawaited(_vpn.stop());
        return;
      }
      _apply(reply);
    } catch (e) {
      if (!mounted || gen != _opGen) return;
      CampusProxy.instance.address = null;
      state = CampusAccessState(
        route: CampusRoute.unreachable,
        message: '校外访问启动失败：$e',
      );
    }
  }

  /// Answers a captcha / SMS / TOTP step.
  Future<void> answer(String value) async {
    final p = state.pending;
    if (p == null || p.needs == null) return;
    final gen = ++_opGen;
    state = state.copyWith(busy: true);
    try {
      final reply = await _vpn.submit(p.needs!, value);
      if (gen != _opGen) {
        if (reply.running) unawaited(_vpn.stop());
        return;
      }
      _apply(reply);
    } catch (e) {
      if (!mounted || gen != _opGen) return;
      state = state.copyWith(busy: false, message: '验证提交失败：$e');
    }
  }

  Future<void> disconnect() async {
    ++_opGen;
    CampusProxy.instance.address = null;
    await _vpn.stop();
    if (mounted) {
      state = const CampusAccessState(route: CampusRoute.unknown);
    }
  }

  void _apply(VpnReply r) {
    if (!mounted) return;
    if (r.running) {
      CampusProxy.instance.address = r.proxy;
      state = CampusAccessState(
        route: CampusRoute.vpn,
        message: r.clientIp == null ? '已通过校外访问连接' : '已连接（${r.clientIp}）',
      );
    } else if (r.needs != null) {
      state = state.copyWith(busy: false, pending: r, message: r.hint);
    } else {
      CampusProxy.instance.address = null;
      state = CampusAccessState(
        route: CampusRoute.unreachable,
        message: r.error ?? '校外访问连接失败',
      );
    }
  }

  /// Decoded captcha image of the pending step, if any.
  Uint8List? get pendingImage {
    final img = state.pending?.image;
    if (img == null || img.isEmpty) return null;
    try {
      return base64.decode(img);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(_vpn.stop());
    CampusProxy.instance.address = null;
    super.dispose();
  }
}
