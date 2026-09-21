/// Course browsing + selection controller for one account.
///
/// Holds the loaded course rows per kind, drives queries through the
/// account's CourseService, and exposes actions to grab immediately or add a
/// class to the monitor. The whole-school catalogue (全校课程) uses a durable
/// complete snapshot and local search; other kinds keep their live queries.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/constants.dart';
import '../data/course_cache.dart';
import '../data/catalog_repository.dart';
import '../data/course_service.dart';
import '../data/enroll_service.dart';
import '../data/models.dart';
import '../data/monitor_engine.dart';

/// Client-side filters over the loaded rows. The official page filters
/// server-side (XGXKLBDM / KKDWDM / 是否冲突), but the whole list is already in
/// memory here, so filtering locally is instant and needs no extra requests.
/// Catalogue facets and searches use the downloaded snapshot, never the server.
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
    this.catalogComplete = false,
    this.catalogDownloaded = 0,
  });

  final CourseKind kind;
  final String query;
  final List<CourseRow> rows;
  final bool loading;
  final String? error;
  final bool loadedOnce;
  final CourseFilters filters;

  /// Local catalogue page and remote teaching-class count.
  final int page;
  final int totalCount;
  final bool catalogComplete;
  final int catalogDownloaded;

  /// When [rows] came from the on-device cache and a refresh is still
  /// running; null once the list is fresh from the server.
  final DateTime? cachedAt;

  bool get paged => kind.isBrowseOnly;
  int get pageCount => !paged || filteredRows.isEmpty
      ? 0
      : (filteredRows.length / CoursesController.catalogPageSize).ceil();

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

  /// Filtering is computed once per immutable state, not once per list tile.
  late final List<CourseRow> filteredRows = _filterRows();
  late final List<CourseRow> visibleRows = paged
      ? filteredRows
          .skip(page * CoursesController.catalogPageSize)
          .take(CoursesController.catalogPageSize)
          .toList()
      : filteredRows;

  List<CourseRow> _filterRows() {
    final f = filters;
    final q = paged ? query.trim().toLowerCase() : '';
    if (!f.isActive && q.isEmpty) return rows;
    final out = <CourseRow>[];
    for (final r in rows) {
      if (f.publicType != null && r.publicCourseType != f.publicType) continue;
      if (f.department != null && r.departmentName != f.department) continue;
      var classes = r.teachingClasses;
      if (q.isNotEmpty &&
          !r.courseName.toLowerCase().contains(q) &&
          !r.courseNumber.toLowerCase().contains(q)) {
        classes = classes
            .where((tc) => tc.teacherName.toLowerCase().contains(q))
            .toList();
      }
      if (f.hideConflict) {
        classes = classes.where((tc) => !tc.isConflict).toList();
      }
      if (f.onlyOnline) classes = classes.where((tc) => tc.isOnline).toList();
      if (f.onlyAvailable) {
        classes = classes
            .where((tc) => tc.isHeld || !tc.hasCapacityInfo || tc.remaining > 0)
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
    bool? catalogComplete,
    int? catalogDownloaded,
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
        catalogComplete: catalogComplete ?? this.catalogComplete,
        catalogDownloaded: catalogDownloaded ?? this.catalogDownloaded,
        cachedAt: cachedAt == _keep ? this.cachedAt : cachedAt as DateTime?,
      );

  static const _keep = Object();
}

class CoursesController extends StateNotifier<CoursesState> {
  CoursesController(this._ref, this.accountId) : super(CoursesState());

  static const int catalogPageSize = 100;

  final Ref _ref;
  final String accountId;
  CourseService get _course =>
      _ref.read(sessionScopeProvider(accountId)).course;
  CourseCache get _cache => _ref.read(courseCacheProvider);
  EnrollService get _enroll =>
      _ref.read(sessionScopeProvider(accountId)).enroll;
  SessionState get _session => _ref.read(sessionControllerProvider(accountId));
  int _loadGeneration = 0;

  CatalogRepository? _catalog;

  CatalogScope? _catalogScope() {
    final session = _session;
    final student = session.student;
    final batch = session.activeBatch;
    if (student == null || batch == null) return null;
    return CatalogScope(
        accountId: accountId,
        origin: _ref.read(sessionScopeProvider(accountId)).client.origin,
        studentCode: student.studentCode,
        campus: student.campus,
        batchCode: batch.code,
        term: batch.schoolTermName);
  }

  void _showCatalog(CatalogStatus status) {
    if (!mounted || !state.paged) return;
    state = state.copyWith(
      rows: status.rows,
      loading: status.loading,
      loadedOnce: true,
      totalCount: status.total,
      catalogComplete: status.complete,
      catalogDownloaded: status.downloaded,
      cachedAt: status.savedAt,
      error: status.error,
      clearError: status.error == null,
    );
    if (state.page > 0 && state.page >= state.pageCount) {
      state = state.copyWith(page: 0);
    }
  }

  /// Called for enrollment revisions too: complete catalogues remain untouched.
  void scopeChanged() {
    final scope = _catalogScope();
    if (_catalog != null && _catalog!.scope.key != scope?.key) {
      _catalog!.dispose();
      _catalog = null;
      if (state.paged) {
        state = CoursesState(kind: state.kind, query: state.query);
      }
    }
    unawaited(load());
  }

  @override
  void dispose() {
    _loadGeneration++;
    _catalog?.dispose();
    super.dispose();
  }

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
      cachedAt: null,
      catalogComplete: false,
      catalogDownloaded: 0,
      filters: const CourseFilters(),
    );
    _loadGeneration++;
    load();
  }

  void setQuery(String q) => state = state.copyWith(query: q, page: 0);

  void setFilters(CourseFilters f) =>
      state = state.copyWith(filters: f, page: 0);

  Future<void> goToPage(int page) async {
    if (!state.paged || page < 0 || page >= state.pageCount) return;
    state = state.copyWith(page: page);
  }

  /// An explicit user action, unlike entry/search/enrollment invalidation.
  Future<void> refreshCatalogOrCourses() async {
    if (!state.paged) return load();
    await load();
    await _catalog?.refresh();
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
    if (kind.isBrowseOnly) {
      final scope = _catalogScope()!;
      if (_catalog?.scope.key != scope.key) {
        _catalog?.dispose();
        _catalog = CatalogRepository(
          _ref.read(storageProvider),
          _course,
          scope,
          onChanged: _showCatalog,
        );
      }
      state = state.copyWith(kind: kind);
      _showCatalog(_catalog!.status);
      unawaited(_catalog!.ensureLoaded());
      return;
    }
    final cacheKey = CourseCache.key(
      accountId: accountId,
      batchCode: batch.code,
      kind: kind.code,
      query: state.query,
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
      final rows = await _course.fetchCourses(
        kind: kind,
        studentCode: student.studentCode,
        campus: student.campus,
        batchCode: batch.code,
        queryContent: state.query,
      );
      const total = 0;
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        rows: rows,
        totalCount: total,
        loading: false,
        loadedOnce: true,
        cachedAt: null,
      );
      unawaited(_cache.write(cacheKey, [for (final r in rows) r.raw],
          totalCount: total));
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
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

  void removeFromMonitor(TeachingClass tc) => _ref
      .read(sessionScopeProvider(accountId))
      .engine
      .removeWatch(watchIdFor(tc));

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
  ref.listen<int>(
      selectionDataRevisionProvider(id), (_, __) => controller.scopeChanged());
  ref.listen<SessionState>(sessionControllerProvider(id), (previous, next) {
    if (previous?.student?.studentCode != next.student?.studentCode ||
        previous?.student?.campus != next.student?.campus ||
        previous?.activeBatch?.code != next.activeBatch?.code ||
        previous?.activeBatch?.schoolTermName !=
            next.activeBatch?.schoolTermName) {
      controller.scopeChanged();
    }
  });
  return controller;
});
