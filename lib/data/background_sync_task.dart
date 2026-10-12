/// The OS background refresh (Android WorkManager, iOS BGAppRefresh) behind
/// a conditional import: web gets no-ops, everything else the workmanager
/// implementation, which itself only registers on Android and iOS.
library;

import 'background_sync_task_stub.dart'
    if (dart.library.io) 'background_sync_task_io.dart'
    as impl;

/// The unique name (Android) / BGTaskScheduler identifier (iOS; must match
/// `BGTaskSchedulerPermittedIdentifiers` in ios/Runner/Info.plist).
const kBackgroundRefreshTask = 'cn.edu.nwafu.nwafuBksxk.eduRefresh';

/// Whether this platform runs the refresh while the app is closed.
bool get backgroundRefreshSupported => impl.backgroundRefreshSupported;

/// Call once in `main()` before [applyBackgroundRefresh].
Future<void> initBackgroundRefresh() => impl.initBackgroundRefresh();

/// Registers (hours > 0) or cancels (0) the periodic task.
Future<void> applyBackgroundRefresh(int hours) =>
    impl.applyBackgroundRefresh(hours);
