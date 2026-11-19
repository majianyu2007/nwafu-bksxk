// Regression tests locking in bug fixes and edge cases from the v2.1.0 audit.
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/cas_client.dart';
import 'package:nwafu_bksxk/data/course_service.dart';
import 'package:nwafu_bksxk/data/degree_audit.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/enroll_service.dart';
import 'package:nwafu_bksxk/data/ics.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/data/monitor_engine.dart';
import 'package:nwafu_bksxk/data/param_builders.dart';
import 'package:nwafu_bksxk/data/portal_service.dart';
import 'package:test/test.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('{"code":"0"}', 200);
  }

  @override
  void close({bool force = false}) {}
}

class _AlwaysAvailableCourses implements CourseService {
  @override
  Future<TeachingClass> refreshCapacity(
    TeachingClass tc,
    String studentCode,
  ) async {
    return tc.withCapacity(
      classCapacity: 10,
      numberOfSelected: 9,
      isFull: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedEnroll implements EnrollService {
  _ScriptedEnroll({required this.onSubmit, this.onConfirm});

  final Future<EnrollOutcome> Function(AddParamPlan plan) onSubmit;
  final Future<ApiResult> Function(String studentCode)? onConfirm;
  int submits = 0;

  @override
  Future<EnrollOutcome> submitAdd(AddParamPlan plan) {
    submits++;
    return onSubmit(plan);
  }

  @override
  Future<ApiResult> confirmStatus(
    String studentCode, {
    int attempts = 6,
    Duration interval = const Duration(milliseconds: 400),
  }) {
    if (onConfirm != null) return onConfirm!(studentCode);
    return Future.value(
      ApiResult(
        code: '1',
        msg: 'ok',
        data: null,
        dataList: const [],
        totalCount: 0,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TeachingClass _sampleClass(String id, {String courseNumber = 'C001'}) =>
    TeachingClass.fromJson({
      'teachingClassID': id,
      'courseName': '高等数学',
      'courseNumber': courseNumber,
      'classCapacity': '10',
      'numberOfSelected': '10',
      'capacitySuffix': '',
      'hasTest': '0',
      'hasBook': '0',
    });

Watch _watchFor(TeachingClass tc) => Watch(
  id: 'w-${tc.teachingClassId}',
  teachingClass: tc,
  kind: CourseKind.fankc,
  batchCode: 'B1',
  studentCode: '2025010001',
  campus: '01',
);

Future<bool> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
  return true;
}

void main() {
  group('AppError.fromBusiness classification', () {
    test(
      'classifies wrong login credentials as account, not sessionExpired',
      () {
        for (final msg in [
          '登录名或密码不正确',
          '用户名或密码错误',
          '账号或密码不正确',
        ]) {
          final err = AppError.fromBusiness('0', msg);
          expect(err.kind, AppErrorKind.account, reason: 'msg=$msg');
        }
      },
    );

    test('keeps genuine session expiry messages as sessionExpired', () {
      for (final msg in ['未查询到登录信息', '会话已过期，请重新登录', 'token失效']) {
        final err = AppError.fromBusiness('302', msg);
        expect(err.kind, AppErrorKind.sessionExpired, reason: 'msg=$msg');
      }
    });
  });

  group('MonitorEngine regressions', () {
    test(
      'throttle error during submit never leaves watch wedged in grabbing',
      () async {
        final tc = _sampleClass('TC-THROTTLE');
        final enroll = _ScriptedEnroll(
          onSubmit: (_) async => throw AppError(
            AppErrorKind.maintenanceOrThrottle,
            message: '操作过于频繁',
          ),
        );
        final engine = MonitorEngine(
          courseService: _AlwaysAvailableCourses(),
          enrollService: enroll,
          config: const MonitorConfig(
            basePollInterval: Duration(milliseconds: 20),
          ),
        );
        addTearDown(engine.dispose);

        final watch = _watchFor(tc);
        engine.addWatch(watch);
        engine.start();

        expect(await _waitFor(() => !engine.isRunning), isTrue);
        expect(watch.status, isNot(WatchStatus.grabbing));
        expect(watch.status, WatchStatus.watching);
      },
    );

    test(
      'sessionExpired during submit triggers haltForSession and clears grabbing',
      () async {
        final tc = _sampleClass('TC-EXPIRED');
        final enroll = _ScriptedEnroll(
          onSubmit: (_) async => throw AppError(
            AppErrorKind.sessionExpired,
            message: '登录已失效',
          ),
        );
        final engine = MonitorEngine(
          courseService: _AlwaysAvailableCourses(),
          enrollService: enroll,
          config: const MonitorConfig(
            basePollInterval: Duration(milliseconds: 20),
          ),
        );
        addTearDown(engine.dispose);

        final watch = _watchFor(tc);
        engine.addWatch(watch);
        engine.start();

        expect(await _waitFor(() => !engine.isRunning), isTrue);
        expect(engine.stopReason, contains('登录已失效'));
        expect(watch.status, isNot(WatchStatus.grabbing));
      },
    );

    test(
      'confirmStatus rejection (-1 duplicate) stops watch cleanly',
      () async {
        final tc = _sampleClass('TC-CONFIRM-REJECT');
        final enroll = _ScriptedEnroll(
          onSubmit: (plan) async => EnrollOutcome(
            success: true,
            code: '1',
            message: 'queued',
            shape: plan.shape,
          ),
          onConfirm: (_) async => ApiResult(
            code: '-1',
            msg: '该课程已存在预选课程结果中',
            data: null,
            dataList: const [],
            totalCount: 0,
          ),
        );
        final engine = MonitorEngine(
          courseService: _AlwaysAvailableCourses(),
          enrollService: enroll,
          config: const MonitorConfig(
            basePollInterval: Duration(milliseconds: 20),
          ),
        );
        addTearDown(engine.dispose);

        final watch = _watchFor(tc);
        engine.addWatch(watch);
        engine.start();

        expect(
          await _waitFor(() => watch.status == WatchStatus.failed),
          isTrue,
        );
        expect(watch.note, contains('已存在'));
      },
    );
  });

  group('PortalItem HTML decoding', () {
    test('decodes HTML entities in a single pass without double-decoding', () {
      final item = PortalItem.fromRow({
        'title':
            '<p>&ldquo;选课&rdquo; &amp; &amp;lt;script&amp;gt; &#65;&#x42;</p>',
        'content': 'A &lt; B &amp;amp; C',
      });
      expect(item.title, '“选课” & &lt;script&gt; AB');
      expect(item.summary, 'A < B &amp; C');
    });
  });

  group('DegreeAudit progress & shortLeaves', () {
    test('passed zero-goal group reports progress 1.0 and missing 0', () {
      final g = DegreeGroup(
        id: 'G0',
        parentId: '-1',
        name: '免修课组',
        earned: 0,
        goal: 0,
        passed: true,
      );
      expect(g.progress, 1.0);
      expect(g.missing, 0);
      expect(g.short, isFalse);
    });

    test('shortLeaves recurses to deepest short nodes', () {
      final leaf = DegreeGroup(
        id: 'L1',
        parentId: 'P1',
        name: '专业核心课',
        earned: 10,
        goal: 16,
      );
      final parent = DegreeGroup(
        id: 'P1',
        parentId: '-1',
        name: '专业课',
        earned: 10,
        goal: 16,
        children: [leaf],
      );
      final plan = DegreePlan(
        id: 'PLAN1',
        name: '软件工程',
        earned: 10,
        goal: 16,
        groups: [parent],
      );
      expect(plan.shortLeaves.map((g) => g.id), ['L1']);
    });
  });

  group('CourseService.groupFlatRows', () {
    test(
      'merges flat rows by courseNumber in O(N) preserving first-seen order',
      () {
        CourseRow flatRow(String courseNumber, String name, String tcId) =>
            CourseRow(
              courseNumber: courseNumber,
              courseName: name,
              credit: '2',
              courseNatureName: '必修',
              departmentName: '理学院',
              number: 1,
              selected: false,
              teachingClasses: [_sampleClass(tcId, courseNumber: courseNumber)],
              raw: const {'KCH': 'flat'},
            );

        final preGrouped = CourseRow(
          courseNumber: 'C001',
          courseName: '已有tcList课程',
          credit: '3',
          courseNatureName: '必修',
          departmentName: '理学院',
          number: 1,
          selected: false,
          teachingClasses: [_sampleClass('TC-PRE', courseNumber: 'C001')],
          raw: const {'tcList': []},
        );

        final grouped = CourseService.groupFlatRows([
          flatRow('C001', '高数', 'TC-1'),
          flatRow('C002', '大英', 'TC-2'),
          preGrouped,
          flatRow('C001', '高数', 'TC-3'),
          flatRow('C002', '大英', 'TC-4'),
        ]);

        expect(grouped, hasLength(3));
        expect(grouped[0].courseNumber, 'C001');
        expect(
          grouped[0].teachingClasses.map((t) => t.teachingClassId),
          ['TC-1', 'TC-3'],
        );
        expect(grouped[0].number, 2);

        expect(grouped[1].courseNumber, 'C002');
        expect(
          grouped[1].teachingClasses.map((t) => t.teachingClassId),
          ['TC-2', 'TC-4'],
        );

        expect(grouped[2].teachingClasses.single.teachingClassId, 'TC-PRE');
      },
    );
  });

  group('CasClient.recheckPassword fail-closed encryption', () {
    test('refuses to transmit password when WIS_PER_ENC cookie is absent', () async {
      final adapter = _RecordingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final cas = CasClient(cookieJar: CookieJar(), dio: dio);
      addTearDown(() => dio.close(force: true));

      await expectLater(
        () => cas.recheckPassword('secret-pw', '1234'),
        throwsA(
          isA<AppError>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.schemaOrRedirect,
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('examSlot late-evening lone start time', () {
    test('rolls end time into the next day instead of rejecting 22:30', () {
      final slot = examSlot(
        const ExamEntry(courseName: '夜间上机考试', time: '2026-06-20 22:30'),
      );
      expect(slot, isNotNull);
      expect(slot!.start, DateTime.utc(2026, 6, 20, 14, 30)); // 22:30 CST
      expect(slot.end, DateTime.utc(2026, 6, 20, 16, 30)); // 00:30+1 CST
    });
  });
}
