import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/web_env.dart';
import '../data/storage.dart';
import '../data/update_service.dart';
import 'providers.dart';

class UpdatesState {
  const UpdatesState({
    this.app = const UpdateCheck(),
    this.bridge = const UpdateCheck(),
    this.version,
    this.buildNumber = '',
    this.loadingVersion = true,
    this.noticeDismissed = false,
  });

  final UpdateCheck app;
  final UpdateCheck bridge;
  final String? version;
  final String buildNumber;
  final bool loadingVersion;
  final bool noticeDismissed;

  bool get checking =>
      loadingVersion ||
      app.status == UpdateStatus.checking ||
      bridge.status == UpdateStatus.checking;
  bool get showNotice =>
      !noticeDismissed && (app.hasUpdate || bridge.hasUpdate);

  UpdatesState copyWith({
    UpdateCheck? app,
    UpdateCheck? bridge,
    String? version,
    String? buildNumber,
    bool? loadingVersion,
    bool? noticeDismissed,
  }) =>
      UpdatesState(
        app: app ?? this.app,
        bridge: bridge ?? this.bridge,
        version: version ?? this.version,
        buildNumber: buildNumber ?? this.buildNumber,
        loadingVersion: loadingVersion ?? this.loadingVersion,
        noticeDismissed: noticeDismissed ?? this.noticeDismissed,
      );
}

class UpdatesController extends StateNotifier<UpdatesState> {
  UpdatesController({
    required UpdateService service,
    required Storage storage,
    required bool isWeb,
    required bool Function() bridgeInstalled,
    required String? Function() bridgeVersion,
    Future<PackageInfo> Function()? packageInfo,
    DateTime Function()? now,
  })  : _service = service,
        _storage = storage,
        _isWeb = isWeb,
        _bridgeInstalled = bridgeInstalled,
        _bridgeVersion = bridgeVersion,
        _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
        _now = now ?? DateTime.now,
        super(const UpdatesState());

  final UpdateService _service;
  final Storage _storage;
  final bool _isWeb;
  final bool Function() _bridgeInstalled;
  final String? Function() _bridgeVersion;
  final Future<PackageInfo> Function() _packageInfo;
  final DateTime Function() _now;
  bool _busy = false;

  /// Called once by the global provider, not on account/tab changes.
  Future<void> initialize() async {
    _busy = true;
    await _loadVersion();
    _busy = false;
    if (!mounted) return;
    final last = _storage.updateLastCheckMillis();
    final now = _now().millisecondsSinceEpoch;
    if (last == null ||
        now < last ||
        now - last >= const Duration(hours: 24).inMilliseconds) {
      await checkNow();
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await _packageInfo().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      state = state.copyWith(
        version: info.version,
        buildNumber: info.buildNumber,
        loadingVersion: false,
        app: UpdateCheck(currentVersion: info.version),
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        loadingVersion: false,
        app: const UpdateCheck(
          status: UpdateStatus.error,
          message: '无法读取当前应用版本，请重试；仍可打开官方发布页。',
        ),
      );
    }
  }

  /// Manual checks bypass the persisted throttle. Both sources complete
  /// independently, so a GitHub outage cannot suppress a script update.
  Future<void> checkNow() async {
    if (_busy || !mounted) return;
    _busy = true;
    state = state.copyWith(
      app: state.app.checking(),
      bridge: state.bridge.checking(),
      noticeDismissed: false,
    );
    try {
      // Persist attempts, including failures, to avoid repeated startup requests.
      // A preference write failure must never prevent manual update checks.
      try {
        await _storage.setUpdateLastCheckMillis(_now().millisecondsSinceEpoch);
      } catch (_) {}
      if (state.version == null) await _loadVersion();
      if (!mounted) return;
      await Future.wait([_checkApp(), _checkBridge()]);
    } finally {
      _busy = false;
    }
  }

  Future<void> _checkApp() async {
    final version = state.version;
    if (version == null) return;
    final result =
        await _service.checkApp(currentVersion: version, isWeb: _isWeb);
    if (mounted) state = state.copyWith(app: result);
  }

  Future<void> _checkBridge() async {
    final result = await _service.checkBridge(
      isWeb: _isWeb,
      installed: _bridgeInstalled(),
      currentVersion: _bridgeVersion(),
    );
    if (mounted) state = state.copyWith(bridge: result);
  }

  void dismissNotice() => state = state.copyWith(noticeDismissed: true);
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  final service = UpdateService();
  ref.onDispose(service.dispose);
  return service;
});

final updatesProvider =
    StateNotifierProvider<UpdatesController, UpdatesState>((ref) {
  final controller = UpdatesController(
    service: ref.watch(updateServiceProvider),
    storage: ref.watch(storageProvider),
    isWeb: isWebRuntime,
    bridgeInstalled: () => isWebBridgeReady,
    bridgeVersion: () => installedWebBridgeVersion,
  );
  unawaited(Future<void>.microtask(controller.initialize));
  return controller;
});
