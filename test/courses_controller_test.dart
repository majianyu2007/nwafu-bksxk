import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/app/providers.dart';
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/course_service.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/ui/courses_controller.dart';

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
  _SignedInSessionController(super.ref) {
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

void main() {
  test('a stale course response cannot overwrite the newest query', () async {
    final service = _DeferredCourseService();
    final container = ProviderContainer(
      overrides: [
        courseServiceProvider.overrideWithValue(service),
        sessionProvider.overrideWith((ref) => _SignedInSessionController(ref)),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(coursesProvider.notifier);
    controller.setQuery('first');
    final first = controller.load();
    controller.setQuery('second');
    final second = controller.load();

    service.requests['second']!.complete([_row('newest')]);
    await second;
    expect(container.read(coursesProvider).rows.single.courseName, 'newest');

    service.requests['first']!.complete([_row('stale')]);
    await first;
    expect(container.read(coursesProvider).rows.single.courseName, 'newest');
  });
}
