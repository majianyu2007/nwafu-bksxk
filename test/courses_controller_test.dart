import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/app/providers.dart';
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/auth_service.dart';
import 'package:nwafu_bksxk/data/course_service.dart';
import 'package:nwafu_bksxk/data/enroll_service.dart';
import 'package:nwafu_bksxk/data/info_service.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/data/monitor_engine.dart';
import 'package:nwafu_bksxk/data/captcha.dart';
import 'package:nwafu_bksxk/ui/courses_controller.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DeferredCourseService extends CourseService {
  _DeferredCourseService() : super(ApiClient(origin: 'http://localhost'));

  final requests = <String, Completer<List<CourseRow>>>{};

  @override
  Future<List<CourseRow>> fetchCourses({
    required CourseKind kind,
    required String studentCode,
    required String campus,
    required String batchCode,
    String queryContent = '',
    int firstPageSize = 1000,
    int maxPages = 50,
  }) {
    return (requests[queryContent] = Completer<List<CourseRow>>()).future;
  }
}

class _SignedInSessionController extends SessionController {
  _SignedInSessionController(super.ref, super.id) {
    state = SessionState(
      phase: AuthPhase.loggedIn,
      student: StudentInfo(studentCode: 'S', name: 'Student', campus: '01'),
      batches: [batch],
      activeBatch: batch,
    );
  }

  static final batch = ElectiveBatch(
    code: 'B',
    name: 'Batch',
    batchType: '1',
    canSelect: true,
  );
}

CourseRow _row(String name) => CourseRow(
      courseNumber: name,
      courseName: name,
      credit: '1',
      courseNatureName: '',
      departmentName: '',
      number: 0,
      selected: false,
      teachingClasses: const [],
    );

/// A scope whose course service is the deferred fake and whose engine and
/// manager never touch the network.
SessionScope _scope(String id, CourseService course) {
  final client = ApiClient(origin: 'http://localhost');
  final auth = AuthService(client);
  final enroll = EnrollService(client);
  return SessionScope(
    accountId: id,
    client: client,
    auth: auth,
    course: course,
    enroll: enroll,
    info: InfoService(client),
    manager: SessionManager(
        client: client, auth: auth, solver: OcrCaptchaSolver((_) async => null)),
    engine: MonitorEngine(courseService: course, enrollService: enroll),
  );
}

void main() {
  test('a stale course response cannot overwrite the newest query', () async {
    const id = 'acct';
    final service = _DeferredCourseService();
    SharedPreferences.setMockInitialValues({});
    final storage = Storage(await SharedPreferences.getInstance());
    final container = ProviderContainer(
      overrides: [
        storageProvider.overrideWithValue(storage),
        sessionScopeProvider(id).overrideWithValue(_scope(id, service)),
        sessionControllerProvider(id)
            .overrideWith((ref) => _SignedInSessionController(ref, id)),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(coursesOfProvider(id).notifier);
    controller.setQuery('first');
    final first = controller.load();
    controller.setQuery('second');
    final second = controller.load();

    service.requests['second']!.complete([_row('newest')]);
    await second;
    expect(container.read(coursesOfProvider(id)).rows.single.courseName, 'newest');

    service.requests['first']!.complete([_row('stale')]);
    await first;
    expect(container.read(coursesOfProvider(id)).rows.single.courseName, 'newest');
  });

  test('switching to the whole-school catalogue pages instead of loading whole',
      () {
    final state = CoursesState(kind: CourseKind.qxkc, totalCount: 6381);
    expect(state.paged, isTrue);
    expect(state.pageCount, 64);
    expect(CoursesState(kind: CourseKind.xgxk).paged, isFalse);
  });
}
