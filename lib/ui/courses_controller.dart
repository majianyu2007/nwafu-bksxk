/// Course browsing + selection controller for one account.
///
/// Holds the loaded course rows per kind, drives queries through the
/// account's CourseService, and exposes actions to grab immediately or add a
/// class to the monitor. The whole-school catalogue (全校课程) is paged
/// server-side; every other kind is loaded whole and filtered locally.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/constants.dart';
import '../data/course_cache.dart';
import '../data/course_service.dart';
import '../data/enroll_service.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';

/// Client-side filters over the loaded rows. The official page filters
/// server-side (XGXKLBDM / KKDWDM / 是否冲突), but the whole list is already in
/// memory here, so filtering locally is instant and needs no extra requests.
/// For the paged catalogue the two facets are sent to the server instead.
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

  /// Only MOOC classes (智慧树 / 学习通 / 知到).
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
    this.page = 0,
    this.totalCount = 0,
    this.cachedAt,
  });

  final CourseKind kind;
  final String query;
  final List<CourseRow> rows;
  final bool loading;
  final String? error;
  final bool loadedOnce;
  final CourseFilters filters;

  /// Catalogue paging (全校课程 only): current server page and total rows.
  final int page;
  final int totalCount;

  /// When [rows] came from the on-device cache and a refresh is still
  /// running; null once the list is fresh from the server.
  final DateTime? cachedAt;

  bool get paged => kind.isBrowseOnly;
  int get pageCount =>
      totalCount == 0 ? 0 : (totalCount / CoursesController.catalogPageSize).ceil();

  /// Distinct 通识类别 values in [rows], in first-seen order.
  List<String> get publicTypes => _facet((r) => r.publicCourseType);

  /// Distinct 开课单位 values in [rows], in first-seen order.
  List<String> get departments => _facet((r) => r.departmentName);

  /// Whether any class is a MOOC, so the 网课 chip is worth showing.
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
      if (!paged) {
        if (f.publicType != null && r.publicCourseType != f.publicType) continue;
        if (f.department != null && r.departmentName != f.department) continue;
      }
      var classes = r.teachingClasses;
      if (f.hideConflict) {
        classes = classes.where((tc) => !tc.isConflict).toList();
      }
      if (f.onlyOnline) classes = classes.where((tc) => tc.isOnline).toList();
      if (f.onlyAvailable) {
        classes = classes
            .where(
                (tc) => tc.isHeld || !tc.hasCapacityInfo || tc.remaining > 0)
            .toList();
      }
      if (classes.isEmpty) continue;
      out.add(classes.length == r.teachingClasses.length
          ? r
          : r.withClasses(classes));
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
    int? page,
    int? totalCount,
    Object? cachedAt = _keep,
  }) =>
      CoursesState(
        kind: kind ?? this.kind,
        query: query ?? this.query,
        rows: rows ?? this.rows,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        loadedOnce: loadedOnce ?? this.loadedOnce,
        filters: filters ?? this.filters,
        page: page ?? this.page,
        totalCount: totalCount ?? this.totalCount,
        cachedAt: cachedAt == _keep ? this.cachedAt : cachedAt as DateTime?,
      );

  static const _keep = Object();
}

class CoursesController extends StateNotifier<CoursesState> {
  CoursesController(this._ref, this.accountId) : super(CoursesState());

  static const int catalogPageSize = 100;

  final Ref _ref;
  final String accountId;
  CourseService get _course => _ref.read(sessionScopeProvider(accountId)).course;
  CourseCache get _cache => _ref.read(courseCacheProvider);
  EnrollService get _enroll => _ref.read(sessionScopeProvider(accountId)).enroll;
  SessionState get _session => _ref.read(sessionControllerProvider(accountId));
  int _loadGeneration = 0;

  /// Catalogue facet codes (dictionary codes) sent as queryContent tokens.
  String? _catalogTypeCode;
  String? _catalogDepartmentCode;

  void setKind(CourseKind kind) {
    if (kind == state.kind) return;
    // Filters are category-specific (the catalogue has no capacity or
    // conflict data, and a 网课 switch carried over would hide every row).
    state = state.copyWith(
      kind: kind,
      rows: const [],
      loadedOnce: false,
      clearError: true,
      page: 0,
      totalCount: 0,
      filters: const CourseFilters(),
    );
    _catalogTypeCode = null;
    _catalogDepartmentCode = null;
    load();
  }

  void setQuery(String q) => state = state.copyWith(query: q, page: 0);

  void setFilters(CourseFilters f) => state = state.copyWith(filters: f);

  /// Catalogue facets: names for display, codes for the server.
  void setCatalogFacets({
    String? typeName,
    String? typeCode,
    String? departmentName,
    String? departmentCode,
    bool clearType = false,
    bool clearDepartment = false,
  }) {
    if (clearType) {
      _catalogTypeCode = null;
      state = state.copyWith(filters: state.filters.copyWith(publicType: null));
    } else if (typeCode != null) {
      _catalogTypeCode = typeCode;
      state =
          state.copyWith(filters: state.filters.copyWith(publicType: typeName));
    }
    if (clearDepartment) {
      _catalogDepartmentCode = null;
      state = state.copyWith(filters: state.filters.copyWith(department: null));
    } else if (departmentCode != null) {
      _catalogDepartmentCode = departmentCode;
      state = state.copyWith(
          filters: state.filters.copyWith(department: departmentName));
    }
    state = state.copyWith(page: 0);
    load();
  }

  Future<void> goToPage(int page) async {
    if (!state.paged || page < 0 || page == state.page) return;
    state = state.copyWith(page: page);
    await load();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final session = _session;
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
    final cacheKey = CourseCache.key(
      accountId: accountId,
      batchCode: batch.code,
      kind: kind.code,
      query: kind.isBrowseOnly ? _catalogQueryContent() : state.query,
      page: kind.isBrowseOnly ? state.page : 0,
    );
    // Show the last known rows at once; the fresh list replaces them.
    final cached = state.rows.isEmpty ? _cache.read(cacheKey) : null;
    state = state.copyWith(
      kind: kind,
      loading: true,
      clearError: true,
      rows: cached == null ? null : _rowsFromJson(kind, cached.rows),
      totalCount: cached?.totalCount,
      loadedOnce: cached != null ? true : null,
      cachedAt: cached?.savedAt,
    );
    try {
      final List<CourseRow> rows;
      var total = 0;
      if (kind.isBrowseOnly) {
        final result = await _course.fetchCatalogPage(
          studentCode: student.studentCode,
          campus: student.campus,
          batchCode: batch.code,
          queryContent: _catalogQueryContent(),
          pageSize: catalogPageSize,
          pageNumber: state.page,
        );
        rows = result.rows;
        total = result.totalCount;
      } else {
        rows = await _course.fetchCourses(
          kind: kind,
          studentCode: student.studentCode,
          campus: student.campus,
          batchCode: batch.code,
          queryContent: state.query,
        );
      }
      if (generation != _loadGeneration) return;
      state = state.copyWith(
        rows: rows,
        totalCount: total,
        loading: false,
        loadedOnce: true,
        cachedAt: null,
      );
      unawaited(_cache.write(cacheKey, [for (final r in rows) r.raw], totalCount: total));
    } catch (e) {
      if (generation != _loadGeneration) return;
      // Keep the cached rows on screen; the banner explains the failed refresh.
      state = state.copyWith(error: '$e', loading: false, loadedOnce: true);
    }
  }

  /// Rebuilds rows from cached raw JSON the way the service does for a fresh
  /// response, so cached and fresh lists look identical.
  static List<CourseRow> _rowsFromJson(
      CourseKind kind, List<Map<String, dynamic>> raws) {
    final rows = <CourseRow>[];
    for (final raw in raws) {
      final flat = !raw.containsKey('tcList') && raw['teachingClassID'] != null;
      if (flat) {
        final tc = TeachingClass.fromJson(raw);
        rows.add(CourseRow(
          courseNumber: tc.courseNumber,
          courseName: tc.courseName,
          credit: (raw['credit'] ?? '').toString(),
          courseNatureName: (raw['courseNatureName'] ?? '').toString(),
          departmentName: (raw['departmentName'] ?? '').toString(),
          number: 1,
          selected: tc.isHeld,
          teachingClasses: [tc],
          raw: raw,
        ));
      } else {
        rows.add(CourseRow.fromJson(raw));
      }
    }
    return CourseService.groupFlatRows(rows);
  }

  /// The official whole-school query prepends its facet tokens to the search
  /// text: "XGXKLBDM:<code>,KKDWDM:<code>,<text>".
  String _catalogQueryContent() {
    var content = state.query;
    if (_catalogDepartmentCode != null) {
      content = 'KKDWDM:$_catalogDepartmentCode,$content';
    }
    if (_catalogTypeCode != null) {
      content = 'XGXKLBDM:$_catalogTypeCode,$content';
    }
    return content;
  }

  /// Refreshes live capacity for a single teaching class in-place.
  Future<TeachingClass> refresh(TeachingClass tc) async {
    final student = _session.student;
    if (student == null) return tc;
    final fresh = await _course.refreshCapacity(tc, student.studentCode);
    _replaceTc(fresh);
    return fresh;
  }

  void _replaceTc(TeachingClass fresh) {
    state = state.copyWith(rows: [
      for (final row in state.rows)
        row.withClasses([
          for (final tc in row.teachingClasses)
            tc.teachingClassId == fresh.teachingClassId ? fresh : tc,
        ]),
    ]);
  }

  /// Immediate manual grab (used when a seat is already open).
  Future<EnrollOutcome> grabNow(
    TeachingClass tc, {
    String? testTeachingClassId,
    String? bookSelection,
    String? volunteerGrade,
  }) async {
    final session = _session;
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
    if (outcome.success) bumpSelectionRevision(_ref, accountId);
    return outcome;
  }

  /// The watch id a class would get, so the tile can show its watched state.
  String watchIdFor(TeachingClass tc) =>
      '${_session.activeBatch?.code}:${tc.teachingClassId}';

  /// Adds a teaching class to the monitor for auto-grab.
  Watch addToMonitor(
    TeachingClass tc, {
    String? testTeachingClassId,
    String? bookSelection,
    String? volunteerGrade,
    bool allowConflict = false,
  }) {
    final session = _session;
    final student = session.student!;
    final batch = session.activeBatch!;
    final watch = Watch(
      id: watchIdFor(tc),
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
    );
    _ref.read(sessionScopeProvider(accountId)).engine.addWatch(watch);
    return watch;
  }

  void removeFromMonitor(TeachingClass tc) =>
      _ref.read(sessionScopeProvider(accountId)).engine.removeWatch(watchIdFor(tc));

  /// Volunteer grades the course still accepts (预选 rounds only).
  Future<List<VolunteerGrade>> fetchVolunteerGrades(TeachingClass tc) {
    final session = _session;
    return _course.fetchCourseVolunteerGrades(
      tc: tc,
      studentCode: session.student!.studentCode,
      batchCode: session.activeBatch!.code,
      kind: state.kind,
    );
  }

  /// Loads experiment classes for a class that has hasTest==1.
  Future<List<Map<String, dynamic>>> fetchTestCourses(TeachingClass tc) {
    final session = _session;
    return _course.fetchTestCourses(
      tc: tc,
      studentCode: session.student!.studentCode,
      batchCode: session.activeBatch!.code,
      campus: session.student!.campus,
      kind: state.kind,
    );
  }
}

/// One controller per account, so switching accounts never mixes lists.
final coursesOfProvider =
    StateNotifierProvider.family<CoursesController, CoursesState, String>(
        (ref, id) {
  final controller = CoursesController(ref, id);
  ref.listen<int>(selectionDataRevisionProvider(id), (_, __) => controller.load());
  return controller;
});
