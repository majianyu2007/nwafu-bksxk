/// Providers that expose the shown account's monitor engine reactively to the
/// UI, persist its watch list, bridge its events to notifications, and run the
/// pre-open "plan" orchestration. All are keyed by account id so every
/// signed-in account keeps its own engine, log and plan.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/monitor_engine.dart';
import '../data/notifications.dart';
import 'providers.dart';

/// Emits whenever any watch of [id]'s engine changes state.
final monitorChangesProvider = StreamProvider.family<void, String>(
    (ref, id) => ref.watch(sessionScopeProvider(id)).engine.changes);

/// [id]'s watch list, rebuilt on every engine change and persisted.
final watchesOfProvider = Provider.family<List<Watch>, String>((ref, id) {
  ref.watch(monitorChangesProvider(id));
  final engine = ref.watch(sessionScopeProvider(id)).engine;
  ref.read(storageProvider).setWatchesJson(id, engine.encodeWatches());
  return engine.watches;
});

/// The shown account's watch list.
final watchesProvider = Provider<List<Watch>>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) return const [];
  return ref.watch(watchesOfProvider(id));
});

/// Count of the shown account's watches that are watching or grabbing.
final watchCountProvider = Provider<int>((ref) => ref
    .watch(watchesProvider)
    .where((w) =>
        w.status == WatchStatus.watching || w.status == WatchStatus.grabbing)
    .length);

/// Whether the shown account's engine is running.
final monitorRunningProvider = Provider<bool>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) return false;
  ref.watch(monitorChangesProvider(id));
  return ref.watch(sessionScopeProvider(id)).engine.isRunning;
});

/// Rolling activity log (newest first, capped) kept outside the widget tree
/// so it survives layout switches and tab changes.
class MonitorLog extends StateNotifier<List<MonitorEvent>> {
  MonitorLog(Stream<MonitorEvent> events) : super(const []) {
    _sub = events.listen(_add);
  }

  static const int capacity = 50;
  late final StreamSubscription<MonitorEvent> _sub;

  void _add(MonitorEvent e) {
    if (e.message.isEmpty) return;
    state = [e, ...state.take(capacity - 1)];
  }

  void clear() => state = const [];

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final monitorLogOfProvider =
    StateNotifierProvider.family<MonitorLog, List<MonitorEvent>, String>(
        (ref, id) => MonitorLog(ref.watch(sessionScopeProvider(id)).engine.events));

/// The shown account's log.
final monitorLogProvider = Provider<List<MonitorEvent>>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) return const [];
  return ref.watch(monitorLogOfProvider(id));
});

/// Bridges one account's monitor events to system notifications and the
/// selection-data refresh. The shell reads it for every signed-in account so
/// notifications fire for accounts that are not on screen.
final notificationBridgeProvider = Provider.family<void, String>((ref, id) {
  final engine = ref.watch(sessionScopeProvider(id)).engine;
  final who = ref.read(sessionControllerProvider(id)).displayName;
  final sub = engine.events.listen((e) {
    final w = e.watch;
    switch (e.kind) {
      case MonitorEventKind.grabbed:
        bumpSelectionRevision(ref, id);
        if (w != null) {
          NotificationService.instance.grabbed(
            courseName: w.teachingClass.courseName,
            className: w.teachingClass.displayTitle,
            place: w.teachingClass.teachingPlace,
            who: who,
          );
        }
      case MonitorEventKind.stopped:
        NotificationService.instance.monitorStopped(e.message, who: who);
      case MonitorEventKind.info:
        break;
    }
  });
  ref.onDispose(sub.cancel);
});

/// Plan-mode state: whether we're holding armed plans until the batch opens,
/// and the latest batch-open check result.
class PlanState {
  const PlanState({
    this.armed = false,
    this.batchOpen = false,
    this.lastCheckedAt,
    this.message = '',
  });
  final bool armed;
  final bool batchOpen;
  final DateTime? lastCheckedAt;
  final String message;

  PlanState copyWith({
    bool? armed,
    bool? batchOpen,
    DateTime? lastCheckedAt,
    String? message,
  }) =>
      PlanState(
        armed: armed ?? this.armed,
        batchOpen: batchOpen ?? this.batchOpen,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        message: message ?? this.message,
      );
}

/// Orchestrates pre-open "plan" grabbing for one account: hold armed watches
/// (gate closed), poll batch-open on an interval, and open the gate + fire the
/// instant the batch opens.
class PlanController extends StateNotifier<PlanState> {
  PlanController(this._ref, this.accountId) : super(const PlanState());
  final Ref _ref;
  final String accountId;
  Timer? _timer;

  SessionScope get _scope => _ref.read(sessionScopeProvider(accountId));

  /// Selects plan mode: closes the grab gate and begins polling batch-open.
  /// Starting/stopping monitoring remains the sole responsibility of the main
  /// monitor button, so choosing a mode has no hidden start side effect.
  Future<void> arm({Duration checkInterval = const Duration(seconds: 5)}) async {
    _scope.engine.closeGate();
    state = state.copyWith(armed: true, message: '等待轮次开放');
    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) => _check());
    await _check();
  }

  /// Cancels plan mode: reopens the gate (normal monitoring) and stops polling.
  void disarm() {
    _timer?.cancel();
    _timer = null;
    _scope.engine.openGate(grabNow: false);
    state = state.copyWith(armed: false, message: '');
  }

  Future<void> _check() async {
    final batch = _ref.read(sessionControllerProvider(accountId)).activeBatch;
    if (batch == null) return;
    try {
      final open = await _scope.auth.isBatchOpen(batch.code);
      state = state.copyWith(batchOpen: open, lastCheckedAt: DateTime.now());
      if (open && state.armed) {
        _scope.engine.openGate(grabNow: true);
        _timer?.cancel();
        _timer = null;
        state = state.copyWith(armed: false, message: '轮次已开放，已开始提交');
      }
    } catch (_) {
      state = state.copyWith(message: '检查开放状态失败，稍后重试');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final planControllerOfProvider =
    StateNotifierProvider.family<PlanController, PlanState, String>(
        (ref, id) => PlanController(ref, id));

/// The shown account's plan state.
final planStateProvider = Provider<PlanState>((ref) {
  final id = ref.watch(activeAccountIdProvider);
  if (id == null) return const PlanState();
  return ref.watch(planControllerOfProvider(id));
});
