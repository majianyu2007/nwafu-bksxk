// Verifies the auto-grab engine: it grabs when a seat opens, only once, and
// blocks watches that lack a required test class / textbook. Also covers the
// safety rules: hard-stop on maintenance/throttle, no double-submit, and that a
// grab is only declared successful when the server confirms it. Uses fakes so no
// network is involved and timing is deterministic.
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/course_service.dart';
import 'package:nwafu_bksxk/data/enroll_service.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/data/monitor_engine.dart';
import 'package:nwafu_bksxk/data/param_builders.dart';
import 'package:test/test.dart';

/// A CourseService test double that returns scripted capacities, and can throw.
class FakeCourseService implements CourseService {
  FakeCourseService(this._script, {this.throwOnPoll});

  /// Per teachingClassId: a queue of remaining-seat counts to return in order.
  final Map<String, List<int>> _script;
  final Map<String, int> _calls = {};

  /// If set, refreshCapacity throws this instead of returning.
  final AppError? throwOnPoll;

  @override
  Future<TeachingClass> refreshCapacity(TeachingClass tc, String studentCode) async {
    if (throwOnPoll != null) throw throwOnPoll!;
    final id = tc.teachingClassId;
    final seq = _script[id] ?? const [0];
    final i = (_calls[id] ?? 0).clamp(0, seq.length - 1);
    _calls[id] = (i + 1);
    final remaining = seq[i];
    // Represent remaining via capacity - selected.
    return tc.withCapacity(classCapacity: 10, numberOfSelected: 10 - remaining, isFull: remaining <= 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An EnrollService double that records submissions and returns a scripted result.
class FakeEnrollService implements EnrollService {
  FakeEnrollService({this.succeed = true, this.outcomeCode, this.outcomeMsg, this.confirmOk = true, this.submitDelay = Duration.zero});
  final bool succeed;
  final String? outcomeCode;
  final String? outcomeMsg;
  final bool confirmOk;
  final Duration submitDelay;
  final List<AddParamPlan> submitted = [];
  int confirmCalls = 0;

  @override
  Future<EnrollOutcome> submitAdd(AddParamPlan plan) async {
    submitted.add(plan);
    if (submitDelay > Duration.zero) await Future<void>.delayed(submitDelay);
    return EnrollOutcome(
      success: succeed,
      code: outcomeCode ?? (succeed ? '1' : '0'),
      message: outcomeMsg ?? (succeed ? 'ok' : 'full'),
      shape: plan.shape,
    );
  }

  @override
  Future<ApiResult> confirmStatus(String studentCode, {int attempts = 6, Duration interval = const Duration(milliseconds: 400)}) async {
    confirmCalls++;
    return ApiResult(code: confirmOk ? '1' : '0', msg: confirmOk ? 'done' : '未成功', data: null, dataList: const [], totalCount: 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TeachingClass plainTc(String id) => TeachingClass.fromJson({
      'teachingClassID': id,
      'courseName': 'C-$id',
      'courseNumber': 'N-$id',
      'classCapacity': '10',
      'numberOfSelected': '10',
      'capacitySuffix': 'sfx',
      'hasTest': '0',
      'hasBook': '0',
    });

Watch watchFor(TeachingClass tc) => Watch(
      id: 'w-${tc.teachingClassId}',
      teachingClass: tc,
      kind: CourseKind.fankc,
      batchCode: 'B',
      studentCode: 'S',
      campus: 'CA',
    );

void main() {
  test('grabs once when a seat opens, then stops', () async {
    // Seat closed, closed, then opens.
    final course = FakeCourseService({'TC1': [0, 0, 1, 1]});
    final enroll = FakeEnrollService(succeed: true);
    final engine = MonitorEngine(
      courseService: course,
      enrollService: enroll,
      config: const MonitorConfig(
        basePollInterval: Duration(milliseconds: 5),
        minPollInterval: Duration(milliseconds: 5),
        jitter: Duration.zero,
      ),
    );

    engine.addWatch(watchFor(plainTc('TC1')));
    engine.start();

    // Wait until the watch reaches a terminal grabbed state.
    final grabbed = await _waitFor(
      () => engine.watches.first.status == WatchStatus.grabbed,
      timeout: const Duration(seconds: 2),
    );
    engine.stop();

    expect(grabbed, isTrue, reason: 'watch should end up grabbed');
    expect(enroll.submitted.length, 1, reason: 'exactly one submit');
    expect(engine.watches.first.status, WatchStatus.grabbed);
    engine.dispose();
  });

  test('watch needing a test class is flagged needsSetup, never grabs', () async {
    final tc = TeachingClass.fromJson({
      'teachingClassID': 'TCX',
      'courseName': 'Lab',
      'classCapacity': '10',
      'numberOfSelected': '0', // seat is open...
      'capacitySuffix': 'sfx',
      'hasTest': '1', // ...but a test class must be chosen first
      'testTeachingClassID': '',
      'hasBook': '0',
    });
    final course = FakeCourseService({'TCX': [5, 5, 5]});
    final enroll = FakeEnrollService(succeed: true);
    final engine = MonitorEngine(
      courseService: course,
      enrollService: enroll,
      config: const MonitorConfig(basePollInterval: Duration(milliseconds: 5), jitter: Duration.zero),
    );

    engine.addWatch(watchFor(tc));
    engine.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    engine.stop();

    expect(engine.watches.first.status, WatchStatus.needsSetup);
    expect(enroll.submitted, isEmpty, reason: 'must not grab without test class');
    engine.dispose();
  });

  test('configureWatch resolves needsSetup and lets it grab', () async {
    final tc = TeachingClass.fromJson({
      'teachingClassID': 'TCY',
      'courseName': 'Lab2',
      'classCapacity': '10',
      'numberOfSelected': '9',
      'capacitySuffix': 'sfx',
      'hasTest': '1',
      'testTeachingClassID': '',
      'hasBook': '0',
    });
    final course = FakeCourseService({'TCY': [1, 1, 1, 1]});
    final enroll = FakeEnrollService(succeed: true);
    final engine = MonitorEngine(
      courseService: course,
      enrollService: enroll,
      config: const MonitorConfig(basePollInterval: Duration(milliseconds: 5), jitter: Duration.zero),
    );

    final w = watchFor(tc);
    engine.addWatch(w);
    expect(engine.watches.first.status, WatchStatus.needsSetup);

    engine.start();
    engine.configureWatch(w.id, testTeachingClassId: 'LAB-1');

    final grabbed = await _waitFor(
      () => engine.watches.first.status == WatchStatus.grabbed,
      timeout: const Duration(seconds: 2),
    );
    engine.stop();

    expect(grabbed, isTrue);
    expect(enroll.submitted.single.testTeachingClassId, 'LAB-1');
    engine.dispose();
  });

  test('maintenance/throttle response hard-stops the whole engine', () async {
    // Seat is open, but the submit comes back with a throttle message.
    final course = FakeCourseService({'TCM': [3, 3, 3, 3]});
    final enroll = FakeEnrollService(succeed: false, outcomeCode: '0', outcomeMsg: '系统繁忙，请稍后再试');
    final engine = MonitorEngine(
      courseService: course,
      enrollService: enroll,
      config: const MonitorConfig(basePollInterval: Duration(milliseconds: 5), jitter: Duration.zero),
    );
    engine.addWatch(watchFor(plainTc('TCM')));
    engine.start();

    final halted = await _waitFor(() => !engine.isRunning, timeout: const Duration(seconds: 2));
    expect(halted, isTrue, reason: 'engine must stop itself on throttle');
    expect(engine.stopReason, isNotNull);
    // It must not keep submitting after being told the system is busy.
    final submitsAtHalt = enroll.submitted.length;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(enroll.submitted.length, submitsAtHalt, reason: 'no submits after hard-stop');
    engine.dispose();
  });

  test('success is only declared when the server confirms it', () async {
    // Submit "succeeds" but confirmStatus says it did not stick.
    final course = FakeCourseService({'TCC': [2, 2, 2, 2]});
    final enroll = FakeEnrollService(succeed: true, confirmOk: false);
    final engine = MonitorEngine(
      courseService: course,
      enrollService: enroll,
      config: const MonitorConfig(basePollInterval: Duration(milliseconds: 5), jitter: Duration.zero),
    );
    engine.addWatch(watchFor(plainTc('TCC')));
    engine.start();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    engine.stop();

    // It must NOT be marked grabbed on an unconfirmed submit.
    expect(engine.watches.first.status, isNot(WatchStatus.grabbed));
    expect(enroll.confirmCalls, greaterThan(0), reason: 'confirmStatus must be consulted');
    engine.dispose();
  });

  test('a slow submit is not double-fired by the next tick', () async {
    // Seat stays open and submit is slow; the fast poll interval would fire a
    // second grab if the in-flight guard were missing.
    final course = FakeCourseService({'TCD': List.filled(20, 5)});
    final enroll = FakeEnrollService(succeed: true, submitDelay: const Duration(milliseconds: 60));
    final engine = MonitorEngine(
      courseService: course,
      enrollService: enroll,
      config: const MonitorConfig(basePollInterval: Duration(milliseconds: 3), jitter: Duration.zero),
    );
    engine.addWatch(watchFor(plainTc('TCD')));
    engine.start();
    await _waitFor(() => engine.watches.first.status == WatchStatus.grabbed, timeout: const Duration(seconds: 2));
    engine.stop();
    expect(enroll.submitted.length, 1, reason: 'in-flight guard prevents double submit');
    engine.dispose();
  });
}

Future<bool> _waitFor(bool Function() cond, {required Duration timeout}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return cond();
}
