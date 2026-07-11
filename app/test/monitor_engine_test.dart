// Verifies the auto-grab engine: it grabs when a seat opens, only once, and
// blocks watches that lack a required test class / textbook. Uses fakes so no
// network is involved and timing is deterministic.
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/data/course_service.dart';
import 'package:nwafu_bksxk/data/enroll_service.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/data/monitor_engine.dart';
import 'package:nwafu_bksxk/data/param_builders.dart';
import 'package:test/test.dart';

/// A CourseService test double that returns scripted capacities.
class FakeCourseService implements CourseService {
  FakeCourseService(this._script);

  /// Per teachingClassId: a queue of remaining-seat counts to return in order.
  final Map<String, List<int>> _script;
  final Map<String, int> _calls = {};

  @override
  Future<TeachingClass> refreshCapacity(TeachingClass tc, String studentCode) async {
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
  FakeEnrollService({this.succeed = true});
  final bool succeed;
  final List<AddParamPlan> submitted = [];

  @override
  Future<EnrollOutcome> submitAdd(AddParamPlan plan) async {
    submitted.add(plan);
    return EnrollOutcome(
      success: succeed,
      code: succeed ? '1' : '0',
      message: succeed ? 'ok' : 'full',
      shape: plan.shape,
    );
  }

  @override
  Future<ApiResult> confirmStatus(String studentCode, {int attempts = 6, Duration interval = const Duration(milliseconds: 400)}) async {
    return ApiResult(code: '1', msg: 'done', data: null, dataList: const [], totalCount: 0);
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
}

Future<bool> _waitFor(bool Function() cond, {required Duration timeout}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return cond();
}
