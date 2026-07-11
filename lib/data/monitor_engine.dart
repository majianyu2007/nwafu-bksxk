/// The monitor / auto-grab engine.
///
/// A [Watch] is a user's request to grab a specific teaching class as soon as a
/// seat appears. The [MonitorEngine] polls each watch's capacity on a cadence
/// and, the moment `remaining > 0`, fires the *pre-resolved* add param. Because
/// the param (including any experiment class / textbook string) is resolved when
/// the watch is armed — not when the seat opens — the grab is a single POST with
/// no branching in the hot path.
///
/// Design points for speed and safety:
///  - Per-watch poll loops run concurrently (independent Futures), so one slow
///    course never delays another.
///  - A jittered, configurable interval avoids hammering and thundering-herd.
///  - Each watch grabs at most once (success -> done); transient failures retry.
///  - The engine is transport-agnostic: it takes the services it needs, so it
///    runs identically in foreground or a background isolate/task.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../core/constants.dart';
import '../core/errors.dart';
import 'course_service.dart';
import 'enroll_service.dart';
import 'models.dart';
import 'param_builders.dart';

/// Lifecycle state of a watch.
enum WatchStatus {
  /// Actively polling for an open seat.
  watching,

  /// A seat opened and the grab is being submitted right now.
  grabbing,

  /// Successfully grabbed. Terminal.
  grabbed,

  /// Paused by the user.
  paused,

  /// Could not be armed (missing test class / textbook) — needs user attention.
  needsSetup,

  /// Repeatedly failed in a non-recoverable way. Terminal-ish.
  failed,
}

/// One monitored target.
class Watch {
  Watch({
    required this.id,
    required this.teachingClass,
    required this.kind,
    required this.batchCode,
    required this.studentCode,
    required this.campus,
    this.selectedTestTeachingClassId,
    this.bookSelection,
    this.status = WatchStatus.watching,
    this.lastRemaining = 0,
    this.lastCheckedAt,
    this.attempts = 0,
    this.note = '',
    this.priority = 0,
  });

  final String id;
  TeachingClass teachingClass;
  final CourseKind kind;
  final String batchCode;
  final String studentCode;
  final String campus;

  /// Pre-chosen experiment class (required if teachingClass.hasTest).
  String? selectedTestTeachingClassId;

  /// Pre-built textbook selection string (required if teachingClass.hasBook).
  String? bookSelection;

  WatchStatus status;
  int lastRemaining;
  DateTime? lastCheckedAt;
  int attempts;
  String note;

  /// Higher priority watches are polled slightly more aggressively.
  int priority;

  /// Consecutive transient errors, used to grow the backoff delay. Reset on any
  /// successful poll.
  int consecutiveErrors = 0;

  /// True while a submit is in flight, so a fast second tick can't double-submit
  /// the same seat.
  bool submitInFlight = false;

  /// When the last add/drop result was recorded, and the raw server text — kept
  /// so the user can confirm the outcome and to aid dispute troubleshooting.
  DateTime? lastResultAt;
  String? lastRawResult;

  String get title => '${teachingClass.courseName} · ${teachingClass.displayTitle}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'tc': teachingClass.raw.isNotEmpty ? teachingClass.raw : _minimalTc(),
        'kind': kind.code,
        'batchCode': batchCode,
        'studentCode': studentCode,
        'campus': campus,
        'testId': selectedTestTeachingClassId,
        'book': bookSelection,
        'status': status.name,
        'note': note,
        'priority': priority,
      };

  Map<String, dynamic> _minimalTc() => {
        'teachingClassID': teachingClass.teachingClassId,
        'courseName': teachingClass.courseName,
        'courseNumber': teachingClass.courseNumber,
        'teacherName': teachingClass.teacherName,
        'classCapacity': teachingClass.classCapacity,
        'numberOfSelected': teachingClass.numberOfSelected,
        'hasTest': teachingClass.hasTest ? '1' : '0',
        'hasBook': teachingClass.hasBook ? '1' : '0',
        'capacitySuffix': teachingClass.capacitySuffix,
      };

  factory Watch.fromJson(Map<String, dynamic> j) => Watch(
        id: j['id'] as String,
        teachingClass: TeachingClass.fromJson((j['tc'] as Map).cast<String, dynamic>()),
        kind: CourseKind.fromCode(j['kind'] as String? ?? 'FANKC'),
        batchCode: j['batchCode'] as String? ?? '',
        studentCode: j['studentCode'] as String? ?? '',
        campus: j['campus'] as String? ?? '',
        selectedTestTeachingClassId: j['testId'] as String?,
        bookSelection: j['book'] as String?,
        status: WatchStatus.values.firstWhere(
          (s) => s.name == (j['status'] as String? ?? 'watching'),
          orElse: () => WatchStatus.watching,
        ),
        note: j['note'] as String? ?? '',
        priority: (j['priority'] as num?)?.toInt() ?? 0,
      );
}

/// The semantic type of a monitor event, for notifications and log styling.
enum MonitorEventKind { info, seatOpen, grabbed, failed, stopped }

/// An event emitted by the engine for the UI/log.
class MonitorEvent {
  MonitorEvent(
    this.watchId,
    this.message, {
    this.success,
    required this.at,
    this.kind = MonitorEventKind.info,
    this.watch,
  });
  final String watchId;
  final String message;
  final bool? success;
  final DateTime at;
  final MonitorEventKind kind;

  /// The watch this event concerns, when applicable (for notification detail).
  final Watch? watch;
}

/// Config knobs for polling cadence and safety.
class MonitorConfig {
  const MonitorConfig({
    this.basePollInterval = const Duration(seconds: 3),
    this.minPollInterval = const Duration(milliseconds: 1200),
    this.jitter = const Duration(milliseconds: 800),
    this.maxAttemptsPerWatch = 0,
    this.confirmAfterGrab = true,
    this.maxBackoff = const Duration(minutes: 2),
    this.backoffBase = const Duration(seconds: 2),
    this.rushMode = false,
  });

  /// Baseline seconds between capacity polls for a watch.
  final Duration basePollInterval;

  /// Floor for high-priority watches. Kept >= ~1s so we never hammer the server.
  final Duration minPollInterval;

  /// Random spread added to each interval to avoid synchronized bursts.
  final Duration jitter;

  /// 0 = unlimited grab retries on transient failure.
  final int maxAttemptsPerWatch;

  /// Whether to poll studentstatus.do after a successful submit.
  final bool confirmAfterGrab;

  /// Ceiling for exponential backoff after consecutive errors.
  final Duration maxBackoff;

  /// Backoff unit; delay = backoffBase * 2^(consecutiveErrors-1), capped.
  final Duration backoffBase;

  /// Rush mode: for the opening-minutes stampede when the server buckles under
  /// load. In this mode a "系统繁忙"/throttle or 5xx/timeout is treated as a
  /// TRANSIENT overload — the watch keeps retrying (with backoff) instead of
  /// hard-stopping the engine. Account/captcha errors still hard-stop, because
  /// those genuinely need a human. Off by default (normal mode is conservative).
  final bool rushMode;

  MonitorConfig copyWith({
    Duration? basePollInterval,
    Duration? minPollInterval,
    Duration? jitter,
    int? maxAttemptsPerWatch,
    bool? confirmAfterGrab,
    Duration? maxBackoff,
    Duration? backoffBase,
    bool? rushMode,
  }) =>
      MonitorConfig(
        basePollInterval: basePollInterval ?? this.basePollInterval,
        minPollInterval: minPollInterval ?? this.minPollInterval,
        jitter: jitter ?? this.jitter,
        maxAttemptsPerWatch: maxAttemptsPerWatch ?? this.maxAttemptsPerWatch,
        confirmAfterGrab: confirmAfterGrab ?? this.confirmAfterGrab,
        maxBackoff: maxBackoff ?? this.maxBackoff,
        backoffBase: backoffBase ?? this.backoffBase,
        rushMode: rushMode ?? this.rushMode,
      );

  Map<String, dynamic> toJson() => {
        'basePollMs': basePollInterval.inMilliseconds,
        'minPollMs': minPollInterval.inMilliseconds,
        'jitterMs': jitter.inMilliseconds,
        'maxAttempts': maxAttemptsPerWatch,
        'confirmAfterGrab': confirmAfterGrab,
        'maxBackoffMs': maxBackoff.inMilliseconds,
        'backoffBaseMs': backoffBase.inMilliseconds,
        'rushMode': rushMode,
      };

  factory MonitorConfig.fromJson(Map<String, dynamic> j) => MonitorConfig(
        basePollInterval: Duration(milliseconds: (j['basePollMs'] as num?)?.toInt() ?? 3000),
        minPollInterval: Duration(milliseconds: (j['minPollMs'] as num?)?.toInt() ?? 1200),
        jitter: Duration(milliseconds: (j['jitterMs'] as num?)?.toInt() ?? 800),
        maxAttemptsPerWatch: (j['maxAttempts'] as num?)?.toInt() ?? 0,
        confirmAfterGrab: j['confirmAfterGrab'] as bool? ?? true,
        maxBackoff: Duration(milliseconds: (j['maxBackoffMs'] as num?)?.toInt() ?? 120000),
        backoffBase: Duration(milliseconds: (j['backoffBaseMs'] as num?)?.toInt() ?? 2000),
        rushMode: j['rushMode'] as bool? ?? false,
      );
}

class MonitorEngine {
  MonitorEngine({
    required CourseService courseService,
    required EnrollService enrollService,
    this.config = const MonitorConfig(),
    Random? random,
  })  : _course = courseService,
        _enroll = enrollService,
        _rng = random ?? Random();

  final CourseService _course;
  final EnrollService _enroll;

  /// The active cadence/safety config. Replacing it takes effect on the next
  /// tick (or restart) — in-flight timers keep their current delay.
  MonitorConfig config;
  final Random _rng;

  final Map<String, Watch> _watches = {};
  final Map<String, Timer> _timers = {};
  bool _running = false;

  /// Set when the engine auto-halted (e.g. server maintenance/throttle), so the
  /// UI can explain why monitoring stopped. Cleared on the next start().
  String? _stopReason;
  String? get stopReason => _stopReason;

  final _events = StreamController<MonitorEvent>.broadcast();
  final _changes = StreamController<void>.broadcast();

  /// Log/toast stream.
  Stream<MonitorEvent> get events => _events.stream;

  /// Fires whenever any watch's state changes (for reactive UI).
  Stream<void> get changes => _changes.stream;

  List<Watch> get watches => _watches.values.toList(growable: false);
  bool get isRunning => _running;

  /// When false, the engine polls capacity for display but does NOT submit any
  /// grab — used for pre-open "plan" watches that should fire only once the
  /// batch opens. Flip to true (via [openGate]) the instant the batch opens.
  bool _gateOpen = true;
  bool get gateOpen => _gateOpen;

  /// Opens the grab gate: armed watches sitting on an open seat will grab on
  /// their next (immediate) tick. Optionally re-arms every watch to fire now.
  void openGate({bool grabNow = true}) {
    _gateOpen = true;
    _emit('', '选课已开放，开始提交', kind: MonitorEventKind.info);
    if (grabNow && _running) {
      for (final w in _watches.values) {
        if (w.status == WatchStatus.watching) _schedule(w, immediate: true);
      }
    }
    _changes.add(null);
  }

  /// Closes the gate (plans are armed but held). New engines start open; call
  /// this before adding plan watches you want to hold until batch-open.
  void closeGate() {
    _gateOpen = false;
    _changes.add(null);
  }

  /// Arms a watch. Pre-resolves the add param to catch missing test/textbook
  /// selections up front (sets status=needsSetup instead of failing at grab).
  void addWatch(Watch watch) {
    _watches[watch.id] = watch;
    _validate(watch);
    if (_running && watch.status == WatchStatus.watching) {
      _schedule(watch, immediate: true);
    }
    _changes.add(null);
  }

  void removeWatch(String id) {
    _timers.remove(id)?.cancel();
    _watches.remove(id);
    _changes.add(null);
  }

  void pauseWatch(String id) {
    final w = _watches[id];
    if (w == null) return;
    _timers.remove(id)?.cancel();
    if (w.status == WatchStatus.watching) w.status = WatchStatus.paused;
    _changes.add(null);
  }

  void resumeWatch(String id) {
    final w = _watches[id];
    if (w == null) return;
    if (w.status == WatchStatus.paused || w.status == WatchStatus.needsSetup) {
      _validate(w);
      if (w.status == WatchStatus.watching && _running) {
        _schedule(w, immediate: true);
      }
    }
    _changes.add(null);
  }

  /// Provide/refresh the experiment class or textbook string for a watch that
  /// needs setup, then re-validate.
  void configureWatch(String id, {String? testTeachingClassId, String? bookSelection}) {
    final w = _watches[id];
    if (w == null) return;
    if (testTeachingClassId != null) w.selectedTestTeachingClassId = testTeachingClassId;
    if (bookSelection != null) w.bookSelection = bookSelection;
    _validate(w);
    if (w.status == WatchStatus.watching && _running) _schedule(w, immediate: true);
    _changes.add(null);
  }

  void _validate(Watch w) {
    if (w.status == WatchStatus.grabbed) return;
    try {
      // Dry-run the resolver; throws MissingSelectionError when incomplete.
      resolveAddParam(
        tc: w.teachingClass,
        studentCode: w.studentCode,
        electiveBatchCode: w.batchCode,
        campus: w.campus,
        kind: w.kind,
        selectedTestTeachingClassId: w.selectedTestTeachingClassId,
        bookSelection: w.bookSelection,
      );
      if (w.status == WatchStatus.needsSetup) w.status = WatchStatus.watching;
    } on MissingSelectionError catch (e) {
      w.status = WatchStatus.needsSetup;
      w.note = e.reason;
    }
  }

  /// Starts polling all armed watches.
  void start() {
    if (_running) return;
    _running = true;
    _stopReason = null; // fresh start clears any prior auto-halt reason
    // Reset backoff so a restart after an error storm probes promptly.
    for (final w in _watches.values) {
      w.consecutiveErrors = 0;
      if (w.status == WatchStatus.watching) _schedule(w, immediate: true);
    }
    _emit('', '监控已启动');
    _changes.add(null);
  }

  /// Stops all polling (watches retain their state).
  void stop() {
    _running = false;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _emit('', '监控已停止');
    _changes.add(null);
  }

  Duration _nextInterval(Watch w) {
    final base = w.priority > 0 ? config.minPollInterval : config.basePollInterval;
    final jitterMs = config.jitter.inMilliseconds;
    final extra = jitterMs == 0 ? 0 : _rng.nextInt(jitterMs);
    var interval = base + Duration(milliseconds: extra);

    // Exponential backoff after consecutive errors so a flaky link or a
    // struggling server is not hammered.
    if (w.consecutiveErrors > 0) {
      final factor = 1 << (w.consecutiveErrors - 1); // 2^(n-1)
      final backoff = config.backoffBase * factor;
      final capped = backoff > config.maxBackoff ? config.maxBackoff : backoff;
      if (capped > interval) interval = capped;
    }
    return interval;
  }

  void _schedule(Watch w, {bool immediate = false}) {
    _timers.remove(w.id)?.cancel();
    if (!_running || w.status != WatchStatus.watching) return;
    final d = immediate ? Duration.zero : _nextInterval(w);
    _timers[w.id] = Timer(d, () => _tick(w));
  }

  Future<void> _tick(Watch w) async {
    if (!_running || w.status != WatchStatus.watching) return;
    try {
      final fresh = await _course.refreshCapacity(w.teachingClass, w.studentCode);
      w.teachingClass = fresh;
      w.lastRemaining = fresh.remaining;
      w.lastCheckedAt = DateTime.now();
      w.consecutiveErrors = 0; // healthy poll resets backoff
      _changes.add(null);

      if (fresh.isGrabbable && _gateOpen) {
        await _attemptGrab(w);
      }
    } on AppError catch (e) {
      _onWatchError(w, e);
    } catch (e) {
      // Unknown/transient — count it toward backoff but keep watching.
      w.consecutiveErrors++;
      w.note = '$e';
    } finally {
      if (_running && w.status == WatchStatus.watching) _schedule(w);
    }
  }

  /// Handles a classified error during polling: hard-stop conditions halt the
  /// watch (or the whole engine); everything else backs off and retries.
  void _onWatchError(Watch w, AppError e) {
    w.note = e.message;
    if (e.kind == AppErrorKind.maintenanceOrThrottle) {
      if (config.rushMode) {
        // Opening rush: the server is overloaded, not telling us to go away for
        // good. Keep this watch and back off — do NOT halt the engine. This is
        // still server-friendly because the backoff grows with each failure.
        w.consecutiveErrors++;
        _emit(w.id, '服务器繁忙，稍后重试（抢开模式）：${e.message}', success: false);
        return;
      }
      // Normal mode: the server is telling us to stop. Halt the ENTIRE engine.
      _emit(w.id, '系统繁忙/维护，已停止全部监控以免加重负载：${e.message}', success: false);
      _haltAll('系统繁忙或维护中');
      return;
    }
    if (e.isHardStop) {
      // Captcha / account / session problems can't be fixed by retrying blindly.
      w.status = WatchStatus.failed;
      _timers.remove(w.id)?.cancel();
      _emit(w.id, '需要人工处理，已停止该监控：${e.message}', success: false);
      _changes.add(null);
      return;
    }
    // Retryable: grow backoff.
    w.consecutiveErrors++;
  }

  /// Stops every watch and the engine (used on maintenance/throttle signals).
  void _haltAll(String reason) {
    _running = false;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _stopReason = reason;
    _emit('', reason, success: false, kind: MonitorEventKind.stopped);
    _changes.add(null);
  }

  Future<void> _attemptGrab(Watch w) async {
    // De-dup guard: never let two ticks submit the same seat concurrently.
    if (w.submitInFlight) return;
    w.submitInFlight = true;
    w.status = WatchStatus.grabbing;
    w.attempts++;
    _changes.add(null);
    _emit(w.id, '发现空位，正在抢 ${w.title}');

    try {
      final plan = resolveAddParam(
        tc: w.teachingClass,
        studentCode: w.studentCode,
        electiveBatchCode: w.batchCode,
        campus: w.campus,
        kind: w.kind,
        selectedTestTeachingClassId: w.selectedTestTeachingClassId,
        bookSelection: w.bookSelection,
      );
      final outcome = await _enroll.submitAdd(plan);

      // Trust the server's final word, not just HTTP success. Confirm via
      // studentstatus.do before declaring victory.
      if (outcome.success) {
        var confirmed = true;
        if (config.confirmAfterGrab) {
          final status = await _enroll.confirmStatus(w.studentCode);
          // A non-ok confirmation means the seat did not actually stick.
          confirmed = status.ok;
          if (status.msg.isNotEmpty) w.note = status.msg;
        }
        if (confirmed) {
          w.status = WatchStatus.grabbed;
          w.note = '已抢到 · ${plan.shapeLabel}${w.note.isNotEmpty ? ' · ${w.note}' : ''}';
          w.lastResultAt = DateTime.now();
          w.lastRawResult = outcome.message;
          _timers.remove(w.id)?.cancel();
          _emit(w.id, '🎉 抢课成功：${w.title}', success: true, kind: MonitorEventKind.grabbed, watch: w);
        } else {
          w.status = WatchStatus.watching;
          _emit(w.id, '提交后未确认成功，继续监控：${w.note}', success: false);
        }
      } else {
        // Classify the business rejection to decide stop-vs-continue.
        final err = AppError.fromBusiness(outcome.code, outcome.message);
        w.lastResultAt = DateTime.now();
        w.lastRawResult = '${outcome.code}: ${outcome.message}';
        if (err.kind == AppErrorKind.maintenanceOrThrottle && !config.rushMode) {
          _emit(w.id, '系统繁忙/维护，已停止全部监控：${err.message}', success: false);
          _haltAll('系统繁忙或维护中');
        } else if (err.kind == AppErrorKind.maintenanceOrThrottle) {
          // Rush mode: overload is transient — keep trying with backoff.
          w.status = WatchStatus.watching;
          w.note = err.message;
          w.consecutiveErrors++;
          _emit(w.id, '服务器繁忙，稍后重试（抢开模式）：${err.message}', success: false);
        } else if (err.isHardStop) {
          w.status = WatchStatus.failed;
          w.note = err.message;
          _timers.remove(w.id)?.cancel();
          _emit(w.id, '需要人工处理，已停止该监控：${err.message}', success: false);
        } else if (_capReached(w)) {
          w.status = WatchStatus.failed;
          w.note = err.message;
          _emit(w.id, '抢课失败次数过多，已停止：${w.title}', success: false);
        } else {
          // Seat vanished (courseFull) or a soft rejection — keep watching.
          w.status = WatchStatus.watching;
          w.note = err.message;
          _emit(w.id, '空位已被抢走或提交失败：${err.message}', success: false);
        }
      }
    } on MissingSelectionError catch (e) {
      w.status = WatchStatus.needsSetup;
      w.note = e.reason;
      _emit(w.id, '需要先完成选择：${e.reason}', success: false);
    } on AppError catch (e) {
      _onWatchError(w, e);
    } catch (e) {
      w.note = '$e';
      w.consecutiveErrors++;
      if (_capReached(w)) {
        w.status = WatchStatus.failed;
      } else {
        w.status = WatchStatus.watching;
      }
      _emit(w.id, '抢课异常：$e', success: false);
    } finally {
      w.submitInFlight = false;
      _changes.add(null);
      if (_running && w.status == WatchStatus.watching) _schedule(w);
    }
  }

  bool _capReached(Watch w) =>
      config.maxAttemptsPerWatch > 0 && w.attempts >= config.maxAttemptsPerWatch;

  void _emit(String watchId, String message, {bool? success, MonitorEventKind kind = MonitorEventKind.info, Watch? watch}) {
    _events.add(MonitorEvent(watchId, message, success: success, at: DateTime.now(), kind: kind, watch: watch));
  }

  /// Serialises the watch list for persistence.
  String encodeWatches() => jsonEncode(_watches.values.map((w) => w.toJson()).toList());

  /// Restores watches from persisted JSON (does not auto-start).
  void loadWatches(String json) {
    final list = jsonDecode(json) as List;
    for (final e in list) {
      final w = Watch.fromJson((e as Map).cast<String, dynamic>());
      if (w.status == WatchStatus.grabbing) w.status = WatchStatus.watching;
      _watches[w.id] = w;
      _validate(w);
    }
    _changes.add(null);
  }

  void dispose() {
    stop();
    _events.close();
    _changes.close();
  }
}
