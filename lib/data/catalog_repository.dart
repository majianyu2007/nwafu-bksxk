import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';

import '../core/errors.dart';
import 'course_service.dart';
import 'models.dart';
import 'storage.dart';

/// Every server-side identity input is part of the key; enrollment changes are
/// deliberately not. Term names also isolate deployments that reuse batch ids.
class CatalogScope {
  const CatalogScope(
      {required this.accountId,
      required this.origin,
      required this.studentCode,
      required this.campus,
      required this.batchCode,
      required this.term});
  final String accountId, origin, studentCode, campus, batchCode, term;
  String get key => 'catalog.v1:${jsonEncode([
            accountId,
            origin,
            studentCode,
            campus,
            batchCode,
            term
          ])}';
}

class CatalogStatus {
  const CatalogStatus(
      {this.rows = const [],
      this.downloaded = 0,
      this.total = 0,
      this.complete = false,
      this.loading = false,
      this.savedAt,
      this.error});
  final List<CourseRow> rows;
  final int downloaded, total;
  final bool complete, loading;
  final DateTime? savedAt;
  final String? error;
}

class _Manifest {
  _Manifest(this.generation, this.pages, this.count, this.total, this.at);
  final String generation;
  int pages, count, total;
  final DateTime at;
  Map<String, dynamic> toJson() => {
        'generation': generation,
        'pages': pages,
        'count': count,
        'total': total,
        'at': at.millisecondsSinceEpoch
      };
  factory _Manifest.fromJson(Map<String, dynamic> j) => _Manifest(
      j['generation'] as String,
      j['pages'] as int,
      j['count'] as int,
      j['total'] as int,
      DateTime.fromMillisecondsSinceEpoch(j['at'] as int));
}

/// Sequential bounded requests, durable page checkpoints, and atomic promotion
/// of a completed generation. Complete snapshots never expire or auto-refresh.
class CatalogRepository {
  CatalogRepository(this._storage, this._service, this.scope,
      {this.onChanged}) {
    _complete = _readManifest('complete');
    _staging = _readManifest('staging');
    final completeRows = _readRows(_complete);
    if (completeRows == null) _complete = null;
    if (_staging?.generation == _complete?.generation) _staging = null;
    final partialRows = _readRows(_staging);
    if (partialRows == null) _staging = null;
    _pending = partialRows ?? [];
    _visible = completeRows ?? partialRows ?? [];
    _publish();
  }

  // Matches the official query's small response size, rather than requesting
  // hundreds of the unusually large whole-school teaching-class records.
  static const pageSize = 20;
  final Storage _storage;
  final CourseService _service;
  final CatalogScope scope;
  final void Function(CatalogStatus)? onChanged;
  late CatalogStatus status;
  _Manifest? _complete, _staging;
  List<CourseRow> _visible = [], _pending = [];
  Future<void>? _inFlight;
  bool _disposed = false, _attempted = false;

  String _key(String suffix) => '${scope.key}:$suffix';
  String _pageKey(_Manifest m, int page) => _key('${m.generation}:$page');

  _Manifest? _readManifest(String kind) {
    try {
      final raw = _storage.cacheGet(_key(kind));
      return raw == null
          ? null
          : _Manifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  List<CourseRow>? _readRows(_Manifest? manifest) {
    if (manifest == null) return null;
    try {
      final rows = <CourseRow>[];
      for (var i = 0; i < manifest.pages; i++) {
        final raw = _storage.cacheGet(_pageKey(manifest, i));
        if (raw == null) return null;
        final bytes = const GZipDecoder().decodeBytes(base64Decode(raw));
        final json = jsonDecode(utf8.decode(bytes)) as List;
        rows.addAll(CourseService.catalogRowsFromJson(
            json.map((e) => (e as Map).cast<String, dynamic>())));
      }
      return rows.length == manifest.count ? rows : null;
    } catch (_) {
      return null;
    }
  }

  void _publish({bool loading = false, String? error}) {
    if (_disposed) return;
    final progress = _staging ?? _complete;
    status = CatalogStatus(
        rows: CourseService.groupFlatRows(_visible),
        downloaded: progress?.count ?? 0,
        total: progress?.total ?? 0,
        complete: _complete != null,
        loading: loading,
        savedAt: (_complete ?? _staging)?.at,
        error: error);
    onChanged?.call(status);
  }

  Future<void> ensureLoaded() {
    if (_disposed || _complete != null || _attempted) {
      return _inFlight ?? Future.value();
    }
    return refresh();
  }

  /// Retains the complete snapshot until every replacement page is durable.
  /// If an interrupted generation exists, retry continues its next page.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_inFlight != null) return _inFlight!;
    _attempted = true;
    final done = Completer<void>();
    _inFlight = done.future;
    unawaited(_fill().whenComplete(() {
      _inFlight = null;
      done.complete();
    }));
    return done.future;
  }

  Future<void> _fill() async {
    _staging ??= _Manifest(DateTime.now().microsecondsSinceEpoch.toString(), 0,
        0, 0, DateTime.now());
    var staging = _staging!;
    _publish(loading: true);
    try {
      final seen = {
        for (final r in _pending)
          for (final tc in r.teachingClasses) tc.teachingClassId
      };
      while (!_disposed) {
        if (staging.pages > 0 && staging.count == staging.total) {
          await _promote(staging);
          return;
        }
        final page = await _service.fetchCatalogPage(
            studentCode: scope.studentCode,
            campus: scope.campus,
            batchCode: scope.batchCode,
            pageSize: pageSize,
            pageNumber: staging.pages);
        if (_disposed) return;
        if (staging.pages > 0 && staging.total != page.totalCount) {
          // Offset pagination cannot safely resume across a changed catalog.
          await _discardStaging(staging);
          throw const FormatException('课程目录已变化，请重试以重新下载；原缓存仍可使用');
        }
        if (page.totalCount < 0 ||
            page.rows.length > pageSize ||
            staging.count + page.rows.length > page.totalCount ||
            (page.rows.length < pageSize &&
                staging.count + page.rows.length < page.totalCount)) {
          throw const FormatException('课程分页数据不完整，请重试');
        }
        for (final row in page.rows) {
          for (final tc in row.teachingClasses) {
            if (tc.teachingClassId.isEmpty || !seen.add(tc.teachingClassId)) {
              await _discardStaging(staging);
              throw const FormatException('课程分页重复或缺少教学班标识，请重试');
            }
          }
        }
        final packed = const GZipEncoder().encodeBytes(
            utf8.encode(jsonEncode([for (final r in page.rows) r.raw])),
            level: 6);
        await _storage.cacheSet(
            _pageKey(staging, staging.pages), base64Encode(packed));
        if (_disposed) return;
        final checkpoint = _Manifest(staging.generation, staging.pages + 1,
            staging.count + page.rows.length, page.totalCount, staging.at);
        await _storage.cacheSet(
            _key('staging'), jsonEncode(checkpoint.toJson()));
        _staging = staging = checkpoint;
        _pending.addAll(page.rows);
        if (_complete == null) _visible = _pending;
        if (_disposed) return;
        if (staging.count == staging.total) {
          await _promote(staging);
          return;
        }
        _publish(loading: true);
        // Let rendering and user input run between network/decode/write batches.
        await Future<void>.delayed(Duration.zero);
      }
    } catch (e) {
      _publish(error: e is AppError ? e.message : '$e');
    }
  }

  Future<void> _promote(_Manifest staging) async {
    final previous = _complete;
    await _storage.cacheSet(_key('complete'), jsonEncode(staging.toJson()));
    _complete = staging;
    _visible = _pending;
    _pending = [];
    _staging = null;
    await _storage.cacheRemove(_key('staging'));
    _publish();
    if (previous != null) await _removePages(previous);
  }

  Future<void> _discardStaging(_Manifest manifest) async {
    await _storage.cacheRemove(_key('staging'));
    _staging = null;
    _pending = [];
    await _removePages(manifest);
  }

  Future<void> _removePages(_Manifest manifest) async {
    for (var i = 0; i < manifest.pages; i++) {
      await _storage.cacheRemove(_pageKey(manifest, i));
    }
  }

  void dispose() {
    _disposed = true;
  }
}
