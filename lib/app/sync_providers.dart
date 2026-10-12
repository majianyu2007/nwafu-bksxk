/// Auto refresh, change log, reminder status and system-calendar sync for
/// the 教务 side. The fetch/diff/notify rules live in
/// `data/background_sync.dart`, shared with the OS background task.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/background_sync.dart';
import '../data/background_sync_task.dart';
import '../data/calendar_sync.dart';
import '../data/edu_models.dart';
import '../data/ics.dart' show buildIcs;
import '../data/ics_export.dart';
import '../data/storage.dart';
import '../data/timetable_diff.dart';
import 'edu_providers.dart';
import 'providers.dart';

/// Diff → cache → notify, posting through the app's notification service.
final eduSyncCoreProvider = Provider<EduSyncCore>(
  (ref) => EduSyncCore(
    ref.watch(storageProvider),
    ref.watch(eduNotificationsProvider),
  ),
);

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

class SyncPrefs {
  const SyncPrefs({
    required this.intervalHours,
    required this.timetableAlerts,
    required this.gradeAlerts,
    required this.examReminders,
    required this.backgroundUseDeviceKey,
    required this.calendar,
  });
  final int intervalHours;
  final bool timetableAlerts;
  final bool gradeAlerts;
  final bool examReminders;
  final bool backgroundUseDeviceKey;
  final CalendarSyncOptions calendar;

  static SyncPrefs read(Storage s) => SyncPrefs(
    intervalHours: s.eduSyncIntervalHours(),
    timetableAlerts: s.timetableChangeAlerts(),
    gradeAlerts: s.gradeAlerts(),
    examReminders: s.examReminders(),
    backgroundUseDeviceKey: s.backgroundUseDeviceKey(),
    calendar: CalendarSyncOptions.read(s),
  );
}

class SyncPrefsController extends StateNotifier<SyncPrefs> {
  SyncPrefsController(this._ref)
    : super(SyncPrefs.read(_ref.read(storageProvider)));
  final Ref _ref;
  Storage get _s => _ref.read(storageProvider);

  void _reload() => state = SyncPrefs.read(_s);

  Future<void> setInterval(int hours) async {
    await _s.setEduSyncIntervalHours(hours);
    _reload();
    unawaited(applyBackgroundRefresh(hours));
    _ref.read(autoRefreshProvider).check();
  }

  Future<void> setTimetableAlerts(bool v) async {
    await _s.setTimetableChangeAlerts(v);
    _reload();
  }

  Future<void> setGradeAlerts(bool v) async {
    await _s.setGradeAlerts(v);
    _reload();
  }

  Future<void> setExamReminders(bool v) async {
    await _s.setExamReminders(v);
    _reload();
    await _ref.read(classReminderProvider.notifier).reschedule();
  }

  Future<void> setBackgroundUseDeviceKey(bool v) async {
    await _s.setBackgroundUseDeviceKey(v);
    _reload();
  }

  Future<void> setCalendarEnabled(bool v) async {
    await _s.setCalendarSyncEnabled(v);
    _reload();
    _ref.read(calendarSyncProvider.notifier).schedule(immediate: true);
  }

  Future<void> setCalendarAlarm(int minutes) async {
    await _s.setCalendarAlarmMinutes(minutes);
    _reload();
    _ref.read(calendarSyncProvider.notifier).schedule();
  }

  Future<void> setCalendarIncludeExams(bool v) async {
    await _s.setCalendarIncludeExams(v);
    _reload();
    _ref.read(calendarSyncProvider.notifier).schedule();
  }

  Future<void> setCalendarRange(String range) async {
    await _s.setCalendarRange(range);
    _reload();
    _ref.read(calendarSyncProvider.notifier).schedule();
  }
}

final syncPrefsProvider = StateNotifierProvider<SyncPrefsController, SyncPrefs>(
  (ref) => SyncPrefsController(ref),
);

// ---------------------------------------------------------------------------
// Change log
// ---------------------------------------------------------------------------

class TimetableChangesController extends StateNotifier<List<TimetableDiff>> {
  TimetableChangesController(this._storage, this._accountId)
    : super(
        _accountId == null ? const [] : readChangeLog(_storage, _accountId),
      );
  final Storage _storage;
  final String? _accountId;

  void reload() {
    final id = _accountId;
    state = id == null ? const [] : readChangeLog(_storage, id);
  }

  Future<void> clear() async {
    final id = _accountId;
    if (id == null) return;
    await _storage.setTimetableChangeLog(id, '[]');
    state = const [];
  }
}

/// Recent timetable changes of the signed-in identity, newest first.
final timetableChangesProvider =
    StateNotifierProvider<TimetableChangesController, List<TimetableDiff>>(
      (ref) => TimetableChangesController(
        ref.watch(storageProvider),
        ref.watch(eduSessionProvider.select((s) => s.account?.username)),
      ),
    );

// ---------------------------------------------------------------------------
// Reminder status
// ---------------------------------------------------------------------------

class ReminderStatus {
  const ReminderStatus({
    required this.count,
    required this.until,
    required this.exact,
    required this.inApp,
  });
  final int count;
  final DateTime? until;

  /// Android exact alarms in use.
  final bool exact;

  /// Fired by the running app (Linux / web) instead of the OS.
  final bool inApp;

  String get text {
    if (count == 0) return '未来 7 天没有需要提醒的课程';
    final u = until?.toUtc().add(const Duration(hours: 8));
    final date = u == null
        ? ''
        : '，至 ${u.month.toString().padLeft(2, '0')}/'
              '${u.day.toString().padLeft(2, '0')}';
    final how = inApp ? '（应用运行时提醒）' : '';
    return '已安排 $count 条提醒$date$how';
  }
}

/// Set by [ClassReminderController.reschedule]; null when reminders are off.
final reminderStatusProvider = StateProvider<ReminderStatus?>((ref) => null);

/// Android: whether exact alarms are allowed; null on other platforms.
final exactAlarmProvider = FutureProvider.autoDispose<bool?>(
  (ref) => ref.watch(eduNotificationsProvider).canScheduleExactAlarms(),
);

// ---------------------------------------------------------------------------
// Auto refresh (in-app)
// ---------------------------------------------------------------------------

/// Refreshes timetable, grades and exams when the last sync is older than
/// the chosen interval: shortly after start, on resume and every 15 min
/// while the app runs (desktop usually stays alive in the tray).
class AutoRefresh {
  AutoRefresh(this._ref) {
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => check());
    _startup = Timer(const Duration(seconds: 5), check);
    _lifecycle = AppLifecycleListener(onResume: onResume);
  }

  final Ref _ref;
  Timer? _timer;
  Timer? _startup;
  AppLifecycleListener? _lifecycle;
  bool _running = false;

  /// Picks up what the background task wrote, then refreshes if due.
  Future<void> onResume() async {
    final storage = _ref.read(storageProvider);
    try {
      await storage.reload();
    } catch (_) {}
    _ref.read(timetableProvider.notifier).reloadCached();
    _ref.read(gradesProvider.notifier).reloadCached();
    _ref.read(timetableChangesProvider.notifier).reload();
    await check();
  }

  Future<void> check({bool force = false}) async {
    if (_running) return;
    final storage = _ref.read(storageProvider);
    final id = _ref.read(eduSessionProvider).account?.username;
    if (id == null) return;
    final hours = storage.eduSyncIntervalHours();
    if (!force &&
        !refreshDue(storage.eduLastSync(id), hours, DateTime.now().toUtc())) {
      return;
    }
    _running = true;
    try {
      await _ref.read(timetableProvider.notifier).sync(silent: true);
      await _ref.read(gradesProvider.notifier).sync(silent: true);
      await refreshExams(_ref);
    } catch (_) {
      // Silent: the next tick retries.
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _startup?.cancel();
    _lifecycle?.dispose();
  }
}

final autoRefreshProvider = Provider<AutoRefresh>((ref) {
  final a = AutoRefresh(ref);
  ref.onDispose(a.dispose);
  // Keep the OS task in step with the saved interval.
  unawaited(
    applyBackgroundRefresh(ref.read(storageProvider).eduSyncIntervalHours()),
  );
  return a;
});

/// Fetches the shown term's exams into the cache (for exam reminders and
/// the calendar) without depending on a page watching [examsProvider].
Future<void> refreshExams(Ref ref) async {
  final id = ref.read(eduSessionProvider).account?.username;
  final term = ref.read(timetableProvider).data?.term;
  if (id == null || term == null) return;
  try {
    final list = await ref.read(eduClientProvider).ehall.exams(term);
    if (ref.read(eduSessionProvider).account?.username != id) return;
    await ref
        .read(storageProvider)
        .setEduExams(
          id,
          term.code,
          jsonEncode([for (final e in list) e.toJson()]),
        );
    unawaited(ref.read(classReminderProvider.notifier).reschedule());
    ref.read(calendarSyncProvider.notifier).schedule();
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// System calendar
// ---------------------------------------------------------------------------

class CalendarSyncState {
  const CalendarSyncState({
    this.running = false,
    this.message,
    this.error,
    this.at,
  });
  final bool running;
  final String? message;
  final String? error;
  final DateTime? at;
}

final calendarAdapterProvider = Provider<CalendarAdapter>(
  (ref) => deviceCalendarAdapter(),
);

class CalendarSyncController extends StateNotifier<CalendarSyncState> {
  CalendarSyncController(this._ref) : super(const CalendarSyncState());
  final Ref _ref;
  Timer? _debounce;
  Future<void>? _inflight;
  bool _again = false;

  bool get supported => _ref.read(calendarAdapterProvider).supported;

  /// Runs a sync soon (debounced) when calendar sync is on, or when it was
  /// just turned off and this app's events need removing.
  void schedule({bool immediate = false}) {
    if (!supported) return;
    final s = _ref.read(storageProvider);
    final id = _ref.read(eduSessionProvider).account?.username;
    if (id == null) return;
    if (!s.calendarSyncEnabled() && (s.calendarIndex(id) ?? '{}') == '{}') {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(seconds: 2),
      () => unawaited(syncNow()),
    );
  }

  Future<void> syncNow() async {
    final inflight = _inflight;
    if (inflight != null) {
      _again = true;
      return inflight;
    }
    final run = _run();
    _inflight = run;
    try {
      await run;
    } finally {
      _inflight = null;
      if (_again && mounted) {
        _again = false;
        unawaited(syncNow());
      }
    }
  }

  Future<void> _run() async {
    final storage = _ref.read(storageProvider);
    final id = _ref.read(eduSessionProvider).account?.username;
    final t = _ref.read(timetableProvider).data;
    if (id == null || t == null) {
      state = const CalendarSyncState(error: '暂无课表，请先同步课表');
      return;
    }
    state = CalendarSyncState(running: true, message: state.message);
    try {
      final r = await syncTimetableToCalendar(
        adapter: _ref.read(calendarAdapterProvider),
        storage: storage,
        accountId: id,
        timetable: t,
        exams: cachedExams(storage, id, t.term.code),
      );
      if (!mounted) return;
      state = CalendarSyncState(message: r.summary(), at: DateTime.now());
    } catch (e) {
      if (!mounted) return;
      state = CalendarSyncState(
        error: e is CalendarUnavailable ? e.message : '日历同步失败：$e',
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final calendarSyncProvider =
    StateNotifierProvider<CalendarSyncController, CalendarSyncState>(
      (ref) => CalendarSyncController(ref),
    );

// ---------------------------------------------------------------------------
// ICS export
// ---------------------------------------------------------------------------

/// Builds [t]'s `.ics` and shares / saves / downloads it.
Future<IcsExportOutcome> exportTimetableIcs({
  required TermTimetable t,
  required String accountId,
  required Storage storage,
  int? alarmMinutes,
  bool includeExams = true,
}) {
  final ics = buildIcs(
    t,
    accountId: accountId,
    alarmMinutes: alarmMinutes,
    exams: includeExams
        ? cachedExams(storage, accountId, t.term.code)
        : const <ExamEntry>[],
  );
  return exportIcsFile(ics, icsFileName(t.term.code));
}
