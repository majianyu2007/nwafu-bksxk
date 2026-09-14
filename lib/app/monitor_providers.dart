/// Providers that expose the monitor engine reactively to the UI, plus the
/// watch-list persistence glue and the pre-open "plan" orchestration.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/monitor_engine.dart';
import '../data/notifications.dart';
import '../data/storage.dart';
import 'providers.dart';

/// Emits whenever any watch changes state (capacity tick, grab, etc.).
final monitorChangesProvider = StreamProvider<void>((ref) {
  final engine = ref.watch(monitorEngineProvider);
  return engine.changes;
});

/// The current watch list, rebuilt on every engine change and persisted.
final watchesProvider = Provider<List<Watch>>((ref) {
  ref.watch(monitorChangesProvider);
  final engine = ref.watch(monitorEngineProvider);
  // Persist on each change so a restart restores the watch list.
  final storage = ref.read(storageProvider);
  _persist(storage, engine);
  return engine.watches;
});

void _persist(Storage storage, MonitorEngine engine) {
  // Fire-and-forget; ordering is not critical.
  storage.setWatchesJson(engine.encodeWatches());
}

/// Count of watches that are actively watching or grabbing (for the tab badge).
final watchCountProvider = Provider<int>((ref) {
  final watches = ref.watch(watchesProvider);
  return watches
      .where((w) => w.status == WatchStatus.watching || w.status == WatchStatus.grabbing)
      .length;
});

/// Whether the engine is currently running.
final monitorRunningProvider = Provider<bool>((ref) {
  ref.watch(monitorChangesProvider);
  return ref.watch(monitorEngineProvider).isRunning;
});

/// Stream of human-readable monitor events for the activity log.
final monitorEventsProvider = StreamProvider<MonitorEvent>((ref) {
  final engine = ref.watch(monitorEngineProvider);
  return engine.events;
});

/// Rolling activity log (newest first, capped) kept outside the widget tree
/// so it survives layout switches and tab changes. Created by the root shell
/// on login so events are captured even before the Monitor tab is opened.
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

final monitorLogProvider =
    StateNotifierProvider<MonitorLog, List<MonitorEvent>>(
        (ref) => MonitorLog(ref.watch(monitorEngineProvider).events));

/// Bridges monitor events to system notifications. Kept alive for the app's
/// lifetime by a read in the root shell so notifications fire even when the
/// Monitor tab isn't visible.
final notificationBridgeProvider = Provider<void>((ref) {
  final engine = ref.watch(monitorEngineProvider);
  final sub = engine.events.listen((e) {
    final w = e.watch;
    switch (e.kind) {
      case MonitorEventKind.grabbed:
        ref.read(selectionDataRevisionProvider.notifier).state++;
        if (w != null) {
          NotificationService.instance.grabbed(
            courseName: w.teachingClass.courseName,
            className: w.teachingClass.displayTitle,
            place: w.teachingClass.teachingPlace,
          );
        }
      case MonitorEventKind.seatOpen:
        if (w != null) {
          NotificationService.instance.seatOpen(
            courseName: w.teachingClass.courseName,
            className: w.teachingClass.displayTitle,
            remaining: w.teachingClass.remaining,
          );
        }
      case MonitorEventKind.stopped:
        NotificationService.instance.monitorStopped(e.message);
      case MonitorEventKind.failed:
      case MonitorEventKind.info:
        break;
    }
  });
  ref.onDispose(sub.cancel);
});

/// Plan-mode state: whether we're holding armed plans until the batch opens,
/// and the latest batch-open check result.
class PlanState {
  const PlanState({this.armed = false, this.batchOpen = false, this.checking = false, this.lastCheckedAt, this.message = ''});
  final bool armed;
  final bool batchOpen;
  final bool checking;
  final DateTime? lastCheckedAt;
  final String message;

  PlanState copyWith({bool? armed, bool? batchOpen, bool? checking, DateTime? lastCheckedAt, String? message}) =>
      PlanState(
        armed: armed ?? this.armed,
        batchOpen: batchOpen ?? this.batchOpen,
        checking: checking ?? this.checking,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        message: message ?? this.message,
      );
}

/// Orchestrates pre-open "plan" grabbing: hold armed watches (gate closed),
/// poll batch-open on an interval, and open the gate + fire the instant the
/// batch opens. Lets the user assemble a plan before selection opens and grab at
/// t=0 without re-selecting.
class PlanController extends StateNotifier<PlanState> {
  PlanController(this._ref) : super(const PlanState());
  final Ref _ref;
  Timer? _timer;

  /// Selects plan mode: closes the grab gate and begins polling batch-open.
  /// Starting/stopping monitoring remains the sole responsibility of the main
  /// monitor button, so choosing a mode has no hidden start side effect.
  Future<void> arm({Duration checkInterval = const Duration(seconds: 5)}) async {
    final engine = _ref.read(monitorEngineProvider);
    engine.closeGate();
    state = state.copyWith(armed: true, message: '已进入计划模式，等待选课开放…');
    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) => _check());
    await _check();
  }

  /// Cancels plan mode: reopens the gate (normal monitoring) and stops polling.
  void disarm() {
    _timer?.cancel();
    _timer = null;
    _ref.read(monitorEngineProvider).openGate(grabNow: false);
    state = state.copyWith(armed: false, message: '已退出计划模式');
  }

  Future<void> _check() async {
    final session = _ref.read(sessionProvider);
    final batch = session.activeBatch;
    if (batch == null) return;
    state = state.copyWith(checking: true);
    try {
      final open = await _ref.read(sessionManagerProvider).auth.isBatchOpen(batch.code);
      state = state.copyWith(checking: false, batchOpen: open, lastCheckedAt: DateTime.now());
      if (open && state.armed) {
        // Fire! Open the gate; armed watches on open seats grab immediately.
        _ref.read(monitorEngineProvider).openGate(grabNow: true);
        _timer?.cancel();
        _timer = null;
        state = state.copyWith(armed: false, message: '选课已开放，开始提交计划');
      }
    } catch (_) {
      state = state.copyWith(checking: false, message: '检查开放状态失败，稍后重试');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final planControllerProvider =
    StateNotifierProvider<PlanController, PlanState>((ref) => PlanController(ref));
