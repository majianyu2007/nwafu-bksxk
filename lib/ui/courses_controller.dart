/// Course browsing + selection controller.
///
/// Holds the loaded course rows per kind, drives queries through CourseService,
/// and exposes actions to grab immediately or add a class to the monitor.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/constants.dart';
import '../data/course_service.dart';
import '../data/enroll_service.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';

class CoursesState {
  CoursesState({
    this.kind = CourseKind.fankc,
    this.query = '',
    this.rows = const [],
    this.loading = false,
    this.error,
    this.loadedOnce = false,
  });

  final CourseKind kind;
  final String query;
  final List<CourseRow> rows;
  final bool loading;
  final String? error;
  final bool loadedOnce;

  CoursesState copyWith({
    CourseKind? kind,
    String? query,
    List<CourseRow>? rows,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? loadedOnce,
  }) =>
      CoursesState(
        kind: kind ?? this.kind,
        query: query ?? this.query,
        rows: rows ?? this.rows,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        loadedOnce: loadedOnce ?? this.loadedOnce,
      );
}

class CoursesController extends StateNotifier<CoursesState> {
  CoursesController(this._ref) : super(CoursesState());

  final Ref _ref;
  CourseService get _course => _ref.read(courseServiceProvider);
  EnrollService get _enroll => _ref.read(enrollServiceProvider);

  void setKind(CourseKind kind) {
    if (kind == state.kind) return;
    state = state.copyWith(kind: kind, rows: const [], loadedOnce: false, clearError: true);
    load();
  }

  void setQuery(String q) => state = state.copyWith(query: q);

  Future<void> load() async {
    final session = _ref.read(sessionProvider);
    final student = session.student;
    final batch = session.activeBatch;
    if (student == null || batch == null) {
      state = state.copyWith(error: '请先在首页选择一个选课轮次', loading: false);
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final rows = await _course.fetchCourses(
        kind: state.kind,
        studentCode: student.studentCode,
        campus: student.campus,
        batchCode: batch.code,
        queryContent: state.query,
      );
      state = state.copyWith(rows: rows, loading: false, loadedOnce: true);
    } catch (e) {
      state = state.copyWith(error: '$e', loading: false, loadedOnce: true);
    }
  }

  /// Refreshes live capacity for a single teaching class in-place.
  Future<TeachingClass> refresh(TeachingClass tc) async {
    final student = _ref.read(sessionProvider).student;
    if (student == null) return tc;
    final fresh = await _course.refreshCapacity(tc, student.studentCode);
    _replaceTc(fresh);
    return fresh;
  }

  void _replaceTc(TeachingClass fresh) {
    final rows = [
      for (final row in state.rows)
        CourseRow(
          courseNumber: row.courseNumber,
          courseName: row.courseName,
          credit: row.credit,
          courseNatureName: row.courseNatureName,
          departmentName: row.departmentName,
          number: row.number,
          selected: row.selected,
          teachingClasses: [
            for (final tc in row.teachingClasses)
              tc.teachingClassId == fresh.teachingClassId ? fresh : tc,
          ],
          raw: row.raw,
        ),
    ];
    state = state.copyWith(rows: rows);
  }

  /// Immediate manual grab (used when a seat is already open).
  Future<EnrollOutcome> grabNow(
    TeachingClass tc, {
    String? testTeachingClassId,
    String? bookSelection,
  }) async {
    final session = _ref.read(sessionProvider);
    final student = session.student!;
    final batch = session.activeBatch!;
    return _enroll.addCourse(
      tc: tc,
      studentCode: student.studentCode,
      batchCode: batch.code,
      campus: student.campus,
      kind: state.kind,
      selectedTestTeachingClassId: testTeachingClassId,
      bookSelection: bookSelection,
    );
  }

  /// Adds a teaching class to the monitor for auto-grab.
  Watch addToMonitor(
    TeachingClass tc, {
    String? testTeachingClassId,
    String? bookSelection,
    int priority = 0,
  }) {
    final session = _ref.read(sessionProvider);
    final student = session.student!;
    final batch = session.activeBatch!;
    final watch = Watch(
      id: '${batch.code}:${tc.teachingClassId}',
      teachingClass: tc,
      kind: state.kind,
      batchCode: batch.code,
      studentCode: student.studentCode,
      campus: student.campus,
      selectedTestTeachingClassId: testTeachingClassId,
      bookSelection: bookSelection,
      priority: priority,
    );
    final engine = _ref.read(monitorEngineProvider);
    engine.addWatch(watch);
    return watch;
  }

  /// Loads experiment classes for a class that has hasTest==1.
  Future<List<Map<String, dynamic>>> fetchTestCourses(TeachingClass tc) {
    final session = _ref.read(sessionProvider);
    final student = session.student!;
    final batch = session.activeBatch!;
    return _course.fetchTestCourses(
      tc: tc,
      studentCode: student.studentCode,
      batchCode: batch.code,
      campus: student.campus,
      kind: state.kind,
    );
  }
}

final coursesProvider =
    StateNotifierProvider<CoursesController, CoursesState>((ref) => CoursesController(ref));
