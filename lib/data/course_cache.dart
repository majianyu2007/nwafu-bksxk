/// A small on-device cache of course lists so a tab opens instantly with the
/// last known rows while the fresh list loads. Rows are stored as gzip+base64
/// JSON in SharedPreferences (works on every platform including web, where
/// there is no file system). One entry per (account, round, kind, query, page).
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import 'storage.dart';

class CachedRows {
  const CachedRows({required this.rows, required this.savedAt, this.totalCount = 0});
  final List<Map<String, dynamic>> rows;
  final DateTime savedAt;
  final int totalCount;

  Duration get age => DateTime.now().difference(savedAt);
}

class CourseCache {
  CourseCache(this._storage, {this.maxAge = const Duration(days: 3)});

  final Storage _storage;

  /// Entries older than this are ignored on read.
  final Duration maxAge;

  static String key({
    required String accountId,
    required String batchCode,
    required String kind,
    String query = '',
    int page = 0,
  }) =>
      '$accountId|$batchCode|$kind|$page|${query.trim()}';

  CachedRows? read(String key) {
    final raw = _storage.cacheGet(key);
    if (raw == null) return null;
    try {
      final bytes = const GZipDecoder().decodeBytes(base64Decode(raw));
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      if (DateTime.now().difference(savedAt) > maxAge) return null;
      return CachedRows(
        rows: (j['rows'] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
        savedAt: savedAt,
        totalCount: (j['total'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, List<Map<String, dynamic>> rows,
      {int totalCount = 0}) async {
    final json = jsonEncode({
      'at': DateTime.now().millisecondsSinceEpoch,
      'total': totalCount,
      'rows': rows,
    });
    final packed = const GZipEncoder().encodeBytes(utf8.encode(json), level: 6);
    await _storage.cacheSet(key, base64Encode(packed));
  }

  Future<void> clear() => _storage.cacheClear();
}
