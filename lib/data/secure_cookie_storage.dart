/// A cookie_jar [Storage] backed by the app's secure storage, so the unified
/// identity cookies (CASTGC and the year-long trusted-device mark
/// `MULTIFACTOR_BROWSER_FINGERPRINT`) survive restarts without sitting in
/// plain files. The cookies are bearer credentials.
library;

import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart' as cj;
import 'package:dio/dio.dart';

import 'storage.dart';

class SecureCookieStorage implements cj.Storage {
  SecureCookieStorage(this._storage, this.accountId);
  final Storage _storage;
  final String accountId;
  final _keys = <String>{};
  bool _closed = false;
  bool _cleared = false;
  Future<void> _pending = Future.value();

  /// Stops retired responses from writing or deleting a replacement session.
  /// Explicit sign-out also removes jars that were never loaded this run.
  Future<void> close({bool clear = false}) {
    _closed = true;
    if (clear && !_cleared) {
      _cleared = true;
      final next = _pending.then((_) async {
        final keys = <String>{'.index', '.domains', ..._keys};
        final index = await _storage.eduCookie(accountId, '.index');
        if (index != null) {
          try {
            keys.addAll((jsonDecode(index) as List).cast<String>());
          } on FormatException {
            // Known keys can still be removed if the index is damaged.
          } on TypeError {
            // Do not let damaged metadata block sign-out.
          }
        }
        for (final key in keys) {
          await _storage.deleteEduCookie(accountId, key);
        }
        _keys.clear();
      });
      _pending = next.catchError((Object _) {});
      return next;
    }
    return _pending;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) async {
      if (!_closed) await action();
    });
    _pending = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}

  @override
  Future<String?> read(String key) {
    final next = _pending.then((_) async {
      if (_closed) return null;
      final value = await _storage.eduCookie(accountId, key);
      if (_closed) return null;
      if (value != null) _keys.add(key);
      return value;
    });
    _pending = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<void> write(String key, String value) => _enqueue(() async {
    _keys.add(key);
    await _storage.setEduCookie(accountId, key, value);
  });
  @override
  Future<void> delete(String key) => _enqueue(() async {
    _keys.remove(key);
    await _storage.deleteEduCookie(accountId, key);
  });
  @override
  Future<void> deleteAll(List<String> keys) => _enqueue(() async {
    for (final k in {...keys, ..._keys}) {
      await _storage.deleteEduCookie(accountId, k);
    }
    _keys.clear();
  });
}

/// A [cj.PersistCookieJar] that hydrates any persisted cookies for `uri.host`
/// before saving new ones and serializes jar operations.
///
/// Upstream `cookie_jar` 4.0.x's `PersistCookieJar.saveFromResponse` writes
/// directly into `hostCookies[host]` and persists it without calling `_load`,
/// so any write to a host not yet loaded in this process silently erases all
/// previously stored cookies for that host (such as `CASTGC` and
/// `MULTIFACTOR_BROWSER_FINGERPRINT`).
class SafePersistCookieJar extends cj.PersistCookieJar {
  SafePersistCookieJar({
    super.persistSession = true,
    super.ignoreExpires = false,
    super.storage,
    super.deleteHostCookiesWhenLoadFailed = true,
  });

  Future<void> _tail = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<List<cj.Cookie>> loadForRequest(Uri uri) =>
      _enqueue(() => super.loadForRequest(uri));

  @override
  Future<void> saveFromResponse(Uri uri, List<cj.Cookie> cookies) {
    if (cookies.isEmpty) return Future.value();
    return _enqueue(() async {
      try {
        await super.loadForRequest(uri);
      } catch (_) {
        // Corrupt host entry was already purged by PersistCookieJar._load.
      }
      await super.saveFromResponse(uri, cookies);
    });
  }

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) =>
      _enqueue(() => super.delete(uri, withDomainSharedCookie));

  @override
  Future<void> deleteAll() => _enqueue(() => super.deleteAll());
}

/// RFC 6265-compliant Dio cookie interceptor that scopes every `Set-Cookie`
/// strictly to the response's own origin (`response.realUri`).
///
/// Upstream `dio_cookie_manager` 3.4.x copies `Set-Cookie` headers from `3xx`
/// responses onto every `Location` target URI as well — even across hosts. In
/// CAS flows that causes two bugs:
///  1. `booking-lib`'s `302` (`Set-Cookie: PHPSESSID` + `Location: authserver`)
///     writes `PHPSESSID` under `authserver.nwafu.edu.cn`, which combined with
///     `PersistCookieJar`'s unloaded-host overwrite wipes `CASTGC` and
///     `MULTIFACTOR_BROWSER_FINGERPRINT` on cold start.
///  2. `authserver`'s `302` (`Set-Cookie: CASTGC` + `Location: ehall/...`)
///     leaks the SSO bearer credential onto service hosts.
class OriginScopedCookieManager extends Interceptor {
  OriginScopedCookieManager(this.cookieJar);

  final cj.CookieJar cookieJar;

  static final _setCookieSplitRe = RegExp(r',(?=\s*[^;,\s]+=)');

  static String _formatCookies(List<cj.Cookie> cookies) {
    cookies.sort((a, b) {
      if (a.path == null && b.path == null) return 0;
      if (a.path == null) return -1;
      if (b.path == null) return 1;
      return b.path!.length.compareTo(a.path!.length);
    });
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  static cj.Cookie? _tryParseCookie(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      return cj.Cookie.fromSetCookieValue(trimmed);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCookies(Response<dynamic> response) async {
    final setCookies = response.headers['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return;
    final cookies = <cj.Cookie>[
      for (final header in setCookies)
        for (final part in header.split(_setCookieSplitRe))
          if (_tryParseCookie(part) case final cookie?) cookie,
    ];
    if (cookies.isEmpty) return;
    final realUri = response.requestOptions.uri.resolveUri(response.realUri);
    await cookieJar.saveFromResponse(realUri, cookies);
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final saved = await cookieJar.loadForRequest(options.uri);
      String? existing;
      final existingKeys = <String>[
        for (final key in options.headers.keys)
          if (key.toLowerCase() == 'cookie') key,
      ];
      for (final key in existingKeys) {
        final raw = options.headers.remove(key)?.toString();
        if (raw != null && raw.isNotEmpty) {
          existing = existing == null ? raw : '$existing; $raw';
        }
      }
      final combined = <cj.Cookie>[
        if (existing != null && existing.isNotEmpty)
          ...existing
              .split(';')
              .map(_tryParseCookie)
              .whereType<cj.Cookie>(),
        ...saved,
      ];
      final header = _formatCookies(combined);
      options.headers['cookie'] = header.isNotEmpty ? header : null;
      handler.next(options);
    } catch (e, s) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: e,
          stackTrace: s,
          message: 'Failed to load cookies for the request.',
        ),
        true,
      );
    }
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      await _saveCookies(response);
      handler.next(response);
    } catch (e, s) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.unknown,
          error: e,
          stackTrace: s,
        ),
        true,
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response != null) {
      try {
        await _saveCookies(response);
      } catch (_) {
        // Keep the original DioException intact.
      }
    }
    handler.next(err);
  }
}
