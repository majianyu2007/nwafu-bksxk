import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/storage.dart';

class MemoryEduStorage extends Storage {
  MemoryEduStorage(super.prefs);
  final passwords = <String, String>{};
  final passkeys = <String, String>{};
  final cookies = <String, Map<String, String>>{};
  Future<void> Function(String accountId, String? value)? beforePasswordWrite;
  Future<void> Function(String accountId, String key)? beforeCookieWrite;

  @override
  Future<String?> eduPassword(String accountId) async => passwords[accountId];
  @override
  Future<void> setEduPassword(String accountId, String? value) async {
    await beforePasswordWrite?.call(accountId, value);
    value == null ? passwords.remove(accountId) : passwords[accountId] = value;
  }
  @override
  Future<String?> eduPasskey(String accountId) async => passkeys[accountId];
  @override
  Future<void> setEduPasskey(String accountId, String? value) async {
    value == null ? passkeys.remove(accountId) : passkeys[accountId] = value;
  }
  @override
  Future<String?> eduCookie(String accountId, String key) async =>
      cookies[accountId]?[key];
  @override
  Future<void> setEduCookie(String accountId, String key, String value) async {
    await beforeCookieWrite?.call(accountId, key);
    (cookies[accountId] ??= {})[key] = value;
  }
  @override
  Future<void> deleteEduCookie(String accountId, String key) async {
    cookies[accountId]?.remove(key);
  }
}

/// Exercises the real Dio transforms, cookies, CAS redirects and EMAP parser.
/// Unexpected requests fail here; this fixture never opens a network socket.
class EduProtocol implements HttpClientAdapter {
  final steps = <({String method, String path,
    FutureOr<ResponseBody> Function(RequestOptions) respond})>[];
  final requests = <RequestOptions>[];

  void add(String method, String path,
      FutureOr<ResponseBody> Function(RequestOptions) respond) {
    steps.add((method: method, path: path, respond: respond));
  }

  void reply(String method, String path, Object body,
      {int status = 200, Map<String, List<String>> headers = const {}}) {
    add(method, path, (_) => response(body, status: status, headers: headers));
  }

  static ResponseBody response(Object body,
      {int status = 200, Map<String, List<String>> headers = const {}}) =>
      ResponseBody.fromString(body is String ? body : jsonEncode(body), status,
          headers: {Headers.contentTypeHeader: ['text/plain'], ...headers});

  static Map<String, String> form(RequestOptions request) =>
      Uri.splitQueryString(request.data as String);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    expect(steps, isNotEmpty, reason: 'Unexpected ${options.method} ${options.uri.path}');
    final step = steps.removeAt(0);
    expect(options.method, step.method);
    expect(options.uri.path, step.path);
    return await step.respond(options);
  }

  @override
  void close({bool force = false}) {}
}
