/// A cookie_jar [Storage] backed by the app's secure storage, so the unified
/// identity cookies (CASTGC and the year-long trusted-device mark
/// `MULTIFACTOR_BROWSER_FINGERPRINT`) survive restarts without sitting in
/// plain files. The cookies are bearer credentials.
library;

import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart' as cj;

import 'storage.dart';

class SecureCookieStorage implements cj.Storage {
  SecureCookieStorage(this._storage, this.accountId);
  final Storage _storage;
  final String accountId;
  final _keys = <String>{};
  bool _closed = false;
  Future<void> _pending = Future.value();

  /// Stops retired responses from writing or deleting a replacement session.
  /// Explicit sign-out also removes jars that were never loaded this run.
  Future<void> close({bool clear = false}) {
    _closed = true;
    if (clear) {
      _pending = _pending.then((_) async {
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
  Future<String?> read(String key) async {
    if (_closed) return null;
    final value = await _storage.eduCookie(accountId, key);
    if (_closed) return null;
    if (value != null) _keys.add(key);
    return value;
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
