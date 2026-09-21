import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/catalog_repository.dart';
import 'package:nwafu_bksxk/data/course_service.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:nwafu_bksxk/ui/courses_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Page = ({List<CourseRow> rows, int totalCount});

class _PageService extends CourseService {
  _PageService() : super(ApiClient(origin: 'http://localhost'));
  final requests = <({String batch, int page, Completer<_Page> result})>[];
  final _arrivals = StreamController<int>.broadcast();

  @override
  Future<_Page> fetchCatalogPage(
      {required String studentCode,
      required String campus,
      required String batchCode,
      String queryContent = '',
      int pageSize = 20,
      int pageNumber = 0}) {
    expect(queryContent, isEmpty);
    expect(pageSize, CatalogRepository.pageSize);
    final result = Completer<_Page>();
    requests.add((batch: batchCode, page: pageNumber, result: result));
    _arrivals.add(requests.length);
    return result.future;
  }

  Future<void> requested(int count) async {
    if (requests.length >= count) return;
    await _arrivals.stream.firstWhere((n) => n >= count);
  }
}

CatalogScope _scope(
        {String account = 'A',
        String origin = 'http://localhost',
        String student = 'S',
        String campus = '01',
        String batch = 'B',
        String term = '2026秋'}) =>
    CatalogScope(
        accountId: account,
        origin: origin,
        studentCode: student,
        campus: campus,
        batchCode: batch,
        term: term);

List<CourseRow> _rows(int start, int count, {String prefix = 'old'}) =>
    CourseService.catalogRowsFromJson(List.generate(
        count,
        (i) => {
              'teachingClassID': '$prefix-${start + i}',
              'courseNumber': '$prefix-${(start + i) ~/ 2}',
              'courseName': '$prefix 课程 ${(start + i) ~/ 2}',
              'teacherName': start + i == 21 ? '王老师' : '李老师',
              'departmentName': start + i >= 20 ? '信息学院' : '农学院',
              'publicCourseTypeName': '科技',
            }));

List<String> _ids(CatalogStatus status) => [
      for (final row in status.rows)
        for (final tc in row.teachingClasses) tc.teachingClassId
    ];

void main() {
  late Storage storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = Storage(await SharedPreferences.getInstance());
  });

  test('progressive pages coalesce; complete cache searches never fetch',
      () async {
    final service = _PageService();
    final repo = CatalogRepository(storage, service, _scope());
    final filling = repo.ensureLoaded();
    final duplicate = repo.ensureLoaded();
    expect(service.requests.length, 1);
    service.requests[0].result.complete((rows: _rows(0, 20), totalCount: 23));
    await service.requested(2);
    expect(repo.status.loading, isTrue);
    expect(repo.status.complete, isFalse);
    expect(_ids(repo.status), [for (var i = 0; i < 20; i++) 'old-$i']);
    expect(service.requests[1].page, 1);
    service.requests[1].result.complete((rows: _rows(20, 3), totalCount: 23));
    await Future.wait([filling, duplicate]);
    repo.dispose();

    final offline = _PageService();
    final restored = CatalogRepository(storage, offline, _scope());
    expect(restored.status.complete, isTrue);
    expect(_ids(restored.status), [for (var i = 0; i < 23; i++) 'old-$i']);
    await restored.ensureLoaded();
    final searched = CoursesState(
        kind: CourseKind.qxkc,
        rows: restored.status.rows,
        query: '王老师',
        filters: const CourseFilters(department: '信息学院', publicType: '科技'));
    expect(searched.visibleRows.single.teachingClasses.single.teachingClassId,
        'old-21');
    expect(offline.requests, isEmpty);
    restored.dispose();
  });

  test('timeout retains partial rows and restart resumes next page', () async {
    final service = _PageService();
    final repo = CatalogRepository(storage, service, _scope());
    final filling = repo.ensureLoaded();
    service.requests[0].result.complete((rows: _rows(0, 20), totalCount: 23));
    await service.requested(2);
    service.requests[1].result.completeError(TimeoutException('slow server'));
    await filling;
    expect(_ids(repo.status).length, 20);
    expect(repo.status.error, isNotNull);
    await repo.ensureLoaded();
    expect(service.requests.length, 2); // no query/entry-triggered retry storm
    repo.dispose();

    final restartedService = _PageService();
    final restarted = CatalogRepository(storage, restartedService, _scope());
    expect(_ids(restarted.status).length, 20);
    final resumed = restarted.ensureLoaded();
    expect(restartedService.requests.single.page, 1);
    restartedService.requests.single.result
        .complete((rows: _rows(20, 3), totalCount: 23));
    await resumed;
    expect(restarted.status.complete, isTrue);
    expect(_ids(restarted.status).last, 'old-22');
    restarted.dispose();
  });

  test('refresh promotes atomically and failed refresh keeps old snapshot',
      () async {
    final service = _PageService();
    final repo = CatalogRepository(storage, service, _scope());
    final initial = repo.ensureLoaded();
    service.requests[0].result.complete((rows: _rows(0, 2), totalCount: 2));
    await initial;
    final refresh = repo.refresh();
    service.requests[1].result
        .complete((rows: _rows(0, 20, prefix: 'new'), totalCount: 21));
    await service.requested(3);
    expect(_ids(repo.status), ['old-0', 'old-1']);
    service.requests[2].result.completeError(TimeoutException('offline'));
    await refresh;
    expect(_ids(repo.status), ['old-0', 'old-1']);
    final restored = CatalogRepository(storage, _PageService(), _scope());
    expect(_ids(restored.status), ['old-0', 'old-1']);
    restored.dispose();
    final retry = repo.refresh();
    expect(service.requests[3].page, 1);
    service.requests[3].result
        .complete((rows: _rows(20, 1, prefix: 'new'), totalCount: 21));
    await retry;
    expect(_ids(repo.status), [for (var i = 0; i < 21; i++) 'new-$i']);
    repo.dispose();
  });

  test('account origin campus student batch and term isolate snapshots',
      () async {
    final service = _PageService();
    final repo = CatalogRepository(storage, service, _scope());
    final initial = repo.ensureLoaded();
    service.requests.single.result.complete((rows: _rows(0, 1), totalCount: 1));
    await initial;
    for (final scope in [
      _scope(account: 'other'),
      _scope(origin: 'https://other'),
      _scope(student: 'other'),
      _scope(campus: 'other'),
      _scope(batch: 'other'),
      _scope(term: 'other')
    ]) {
      final other = CatalogRepository(storage, _PageService(), scope);
      expect(other.status.rows, isEmpty);
      expect(other.status.complete, isFalse);
      other.dispose();
    }
    repo.dispose();
  });

  test('repeated server pages stop instead of marking incomplete data complete',
      () async {
    final service = _PageService();
    final repo = CatalogRepository(storage, service, _scope());
    final initial = repo.ensureLoaded();
    service.requests[0].result.complete((rows: _rows(0, 20), totalCount: 40));
    await service.requested(2);
    service.requests[1].result.complete((rows: _rows(0, 20), totalCount: 40));
    await initial;
    expect(repo.status.complete, isFalse);
    expect(repo.status.error, isNotNull);
    expect(_ids(repo.status).length, 20);
    final retry = repo.refresh();
    expect(service.requests[2].page, 0);
    repo.dispose();
    service.requests[2].result.complete((rows: _rows(0, 20), totalCount: 40));
    await retry;
  });

  test('disposed fill neither publishes late pages nor fetches another page',
      () async {
    final service = _PageService();
    final changes = <CatalogStatus>[];
    final repo =
        CatalogRepository(storage, service, _scope(), onChanged: changes.add);
    final initial = repo.ensureLoaded();
    repo.dispose();
    final before = changes.length;
    service.requests[0].result.complete((rows: _rows(0, 20), totalCount: 40));
    await initial;
    expect(changes.length, before);
    expect(service.requests.length, 1);
  });

  test('catalog pagination counts raw classes and preserves all raw records',
      () async {
    final client = _RecordingClient();
    final page = await CourseService(client).fetchCatalogPage(
        studentCode: 'S', campus: '01', batchCode: 'B', pageNumber: 3);
    expect(page.rows.length, 2);
    expect(page.rows.map((r) => r.raw['teachingClassID']), ['old-0', 'old-1']);
    final query = jsonDecode(client.form!['querySetting'] as String) as Map;
    expect(query['pageNumber'], '3');
    expect(query['pageSize'], '20');
    expect(query['data']['teachingClassType'], 'QXKC');
    expect(query['data'].containsKey('checkCapacity'), isFalse);
  });
}

class _RecordingClient extends ApiClient {
  _RecordingClient() : super(origin: 'http://localhost');
  Map<String, dynamic>? form;
  @override
  Future<ApiResult> postForm(String path, Map<String, dynamic> data,
      {bool auth = true,
      bool allowRelogin = true,
      Map<String, dynamic>? query}) async {
    form = data;
    return ApiResult.fromJson({
      'code': '1',
      'totalCount': 62,
      'dataList': [for (final row in _rows(0, 2)) row.raw]
    });
  }
}
