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

/// Client-side filters over the loaded rows. The official page filters
/// server-side (XGXKLBDM / KKDWDM / 是否冲突), but the whole list is already in
/// memory here, so filtering locally is instant and needs no extra requests.
class CourseFilters {
  const CourseFilters({
    this.publicType,
    this.department,
    this.hideConflict = false,
    this.onlyAvailable = false,
    this.onlyOnline = false,
  });

  /// 通识类别 (publicCourseTypeName), null = all.
  final String? publicType;

  /// 开课单位 (departmentName), null = all.
  final String? department;
  final bool hideConflict;

  /// Hide classes with no remaining seats (正选) / first-choice seats (预选).
  final bool onlyAvailable;

  /// Only classes taught with SPOC/MOOC (网课).
  final bool onlyOnline;

  bool get isActive =>
      publicType != null ||
      department != null ||
      hideConflict ||
      onlyAvailable ||
      onlyOnline;

  CourseFilters copyWith({
    Object? publicType = _keep,
    Object? department = _keep,
    bool? hideConflict,
    bool? onlyAvailable,
    bool? onlyOnline,
  }) =>
      CourseFilters(
        publicType:
            publicType == _keep ? this.publicType : publicType as String?,
        department:
            department == _keep ? this.department : department as String?,
        hideConflict: hideConflict ?? this.hideConflict,
        onlyAvailable: onlyAvailable ?? this.onlyAvailable,
        onlyOnline: onlyOnline ?? this.onlyOnline,
      );

  static const _keep = Object();
}

class CoursesState {
  CoursesState({
    this.kind = CourseKind.fankc,
    this.query = '',
    this.rows = const [],
    this.loading = false,
    this.error,
    this.loadedOnce = false,
    this.filters = const CourseFilters(),
  });

  final CourseKind kind;
  final String query;
  final List<CourseRow> rows;
  final bool loading;
  final String? error;
  final bool loadedOnce;
  final CourseFilters filters;

  /// Distinct 通识类别 values in [rows], in first-seen order.
  List<String> get publicTypes => _facet((r) => r.publicCourseType);

  /// Distinct 开课单位 values in [rows], in first-seen order.
  List<String> get departments => _facet((r) => r.departmentName);

  /// Whether any class is taught online, so the 网课 chip is worth showing.
  bool get hasOnline =>
      rows.any((r) => r.teachingClasses.any((tc) => tc.isOnline));

  List<String> _facet(String Function(CourseRow) pick) {
    final seen = <String>{};
    final out = <String>[];
    for (final r in rows) {
      final v = pick(r);
      if (v.isNotEmpty && seen.add(v)) out.add(v);
    }
    return out;
  }

  /// [rows] after [filters]: course-level facets drop whole courses; class-level
  /// switches drop classes and then any course left without classes.
  List<CourseRow> get visibleRows {
    final f = filters;
    if (!f.isActive) return rows;
    final out = <CourseRow>[];
    for (final r in rows) {
      if (f.publicType != null && r.publicCourseType != f.publicType) continue;
      if (f.department != null && r.departmentName != f.department) continue;
      var classes = r.teachingClasses;
      if (f.hideConflict) {
        classes = classes.where((tc) => !tc.isConflict).toList();
      }
      if (f.onlyOnline) classes = classes.where((tc) => tc.isOnline).toList();
      if (f.onlyAvailable) {
        classes = classes
            .where(
                (tc) => tc.isChoose || !tc.hasCapacityInfo || tc.remaining > 0)
            .toList();
      }
      if (classes.isEmpty) continue;
      out.add(classes.length == r.teachingClasses.length
          ? r
          : CourseRow(
              courseNumber: r.courseNumber,
              courseName: r.courseName,
              credit: r.credit,
              courseNatureName: r.courseNatureName,
              departmentName: r.departmentName,
              number: classes.length,
              selected: r.selected,
              teachingClasses: classes,
              raw: r.raw,
            ));
    }
    return out;
  }

  CoursesState copyWith({
    CourseKind? kind,
    String? query,
    List<CourseRow>? rows,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? loadedOnce,
    CourseFilters? filters,
  }) =>
      CoursesState(
        kind: kind ?? this.kind,
        query: query ?? this.query,
        rows: rows ?? this.rows,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        loadedOnce: loadedOnce ?? this.loadedOnce,
        filters: filters ?? this.filters,
      );
}

class CoursesController extends StateNotifier<CoursesState> {
  CoursesController(this._ref) : super(CoursesState());

  final Ref _ref;
  CourseService get _course => _ref.read(courseServiceProvider);
  EnrollService get _enroll => _ref.read(enrollServiceProvider);
  int _loadGeneration = 0;

  void setKind(CourseKind kind) {
    if (kind == state.kind) return;
    // Facet values are category-specific; the switches carry over.
    state = state.copyWith(
      kind: kind,
      rows: const [],
      loadedOnce: false,
      clearError: true,
      filters: state.filters.copyWith(publicType: null, department: null),
    );
    load();
  }

  void setQuery(String q) => state = state.copyWith(query: q);

  void setFilters(CourseFilters f) => state = state.copyWith(filters: f);

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final session = _ref.read(sessionProvider);
    final student = session.student;
    final batch = session.activeBatch;
    if (student == null || batch == null) {
      state = state.copyWith(
        error: '请先在首页选择一个选课轮次',
        loading: false,
        loadedOnce: true,
      );
      return;
    }
    // A round only exposes some kinds (its display* flags); if the current
    // kind is hidden here, fall back to the first one the round shows.
    var kind = state.kind;
    if (!batch.showsKind(kind)) {
      kind = CourseKind.values.firstWhere(batch.showsKind, orElse: () => kind);
    }
    final query = state.query;
    state = state.copyWith(kind: kind, loading: true, clearError: true);
    try {
      final rows = await _course.fetchCourses(
        kind: kind,
        studentCode: student.studentCode,
        campus: student.campus,
        batchCode: batch.code,
        queryContent: query,
      );
      if (generation != _loadGeneration) return;
      state = state.copyWith(rows: rows, loading: false, loadedOnce: true);
    } catch (e) {
      if (generation != _loadGeneration) return;
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
    String? volunteerGrade,
  }) async {
    final session = _ref.read(sessionProvider);
    final student = session.student!;
    final batch = session.activeBatch!;
    final outcome = await _enroll.addCourse(
      tc: tc,
      studentCode: student.studentCode,
      batchCode: batch.code,
      campus: student.campus,
      kind: state.kind,
      selectedTestTeachingClassId: testTeachingClassId,
      bookSelection: bookSelection,
      textbookOrderingOpen: batch.canSelectBook,
      volunteerGrade: volunteerGrade,
    );
    if (outcome.success) {
      _ref.read(selectionDataRevisionProvider.notifier).state++;
    }
    return outcome;
  }

  /// Adds a teaching class to the monitor for auto-grab.
  Watch addToMonitor(
    TeachingClass tc, {
    String? testTeachingClassId,
    String? bookSelection,
    String? volunteerGrade,
    bool allowConflict = false,
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
      textbookOrderingOpen: batch.canSelectBook,
      volunteerGrade: volunteerGrade,
      allowConflict: allowConflict,
      priority: priority,
    );
    final engine = _ref.read(monitorEngineProvider);
    engine.addWatch(watch);
    return watch;
  }

  /// Volunteer grades the course still accepts (预选 rounds only).
  Future<List<VolunteerGrade>> fetchVolunteerGrades(TeachingClass tc) {
    final session = _ref.read(sessionProvider);
    final student = session.student!;
    final batch = session.activeBatch!;
    return _course.fetchCourseVolunteerGrades(
      tc: tc,
      studentCode: student.studentCode,
      batchCode: batch.code,
      kind: state.kind,
    );
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

  void reloadForSelectionChange() => load();
}

final coursesProvider =
    StateNotifierProvider<CoursesController, CoursesState>((ref) {
  final controller = CoursesController(ref);
  ref.listen<int>(selectionDataRevisionProvider, (_, __) {
    controller.reloadForSelectionChange();
  });
  return controller;
});
