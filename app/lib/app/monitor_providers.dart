/// Providers that expose the monitor engine reactively to the UI, plus the
/// watch-list persistence glue.
library;

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

/// Bridges monitor events to system notifications. Kept alive for the app's
/// lifetime by a read in the root shell so notifications fire even when the
/// Monitor tab isn't visible.
final notificationBridgeProvider = Provider<void>((ref) {
  final engine = ref.watch(monitorEngineProvider);
  final sub = engine.events.listen((e) {
    final w = e.watch;
    switch (e.kind) {
      case MonitorEventKind.grabbed:
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
