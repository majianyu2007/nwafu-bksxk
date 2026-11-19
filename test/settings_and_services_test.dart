import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart' show CookieJar;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nwafu_bksxk/app/providers.dart';
import 'package:nwafu_bksxk/app/theme.dart';
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/cas_client.dart';
import 'package:nwafu_bksxk/data/library_service.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:nwafu_bksxk/ui/settings_page.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  test('MfaMethod.byCode supports all nwafu-cas 1.0.1 reAuth types', () {
    expect(MfaMethod.byCode('2'), MfaMethod.password);
    expect(MfaMethod.byCode('7'), MfaMethod.password);
    expect(MfaMethod.byCode('3'), MfaMethod.sms);
    expect(MfaMethod.byCode('4'), MfaMethod.wecom);
    expect(MfaMethod.byCode('5'), MfaMethod.cpdaily);
    expect(MfaMethod.byCode('10'), MfaMethod.totp);
    expect(MfaMethod.byCode('11'), MfaMethod.email);
    expect(MfaMethod.byCode('12'), MfaMethod.dingtalk);
    expect(MfaMethod.byCode('13'), MfaMethod.welink);
    expect(MfaMethod.byCode('15'), MfaMethod.wechatService);
    expect(MfaMethod.byCode('18'), MfaMethod.face);
    expect(MfaMethod.byCode('REAL_PERSON_PLUGIN_WECHAT'), MfaMethod.face);
  });

  test('LibraryService decodes plain-string JSON responses cleanly', () async {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = _FakeAdapter((opts) {
        if (opts.path.contains('/api/cas/cas')) {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': [
                'https://booking-lib.nwafu.edu.cn/h5/index.html#/cas/?cas=T1',
              ],
            },
          );
        }
        if (opts.path.contains('/h5/index.html')) {
          return ResponseBody.fromString('<html></html>', 200);
        }
        if (opts.path.contains('/api/cas/user')) {
          return ResponseBody.fromString(
            jsonEncode({
              'code': 1,
              'member': {'token': 'TOK'},
            }),
            200,
            headers: {
              // Simulate a server sending JSON with text/html Content-Type.
              Headers.contentTypeHeader: ['text/html; charset=utf-8'],
            },
          );
        }
        if (opts.path.contains('/api/Member/my')) {
          return ResponseBody.fromString(
            jsonEncode({
              'code': 1,
              'data': {'name': '测试同学', 'roleName': '本科生'},
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['text/plain'],
            },
          );
        }
        return ResponseBody.fromString('<html>authserver</html>', 200);
      });

    final cas = CasClient(cookieJar: CookieJar(), dio: dio);
    final lib = LibraryService(cas);
    final member = await lib.member();
    expect(member.name, '测试同学');
    expect(member.roleName, '本科生');
  });

  test('LibraryService classifies HTML authserver redirect as sessionExpired',
      () async {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = _FakeAdapter((opts) {
        if (opts.path.contains('/api/cas/cas')) {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': [
                'https://booking-lib.nwafu.edu.cn/h5/index.html#/cas/?cas=T1',
              ],
            },
          );
        }
        if (opts.path.contains('/h5/index.html')) {
          return ResponseBody.fromString('<html></html>', 200);
        }
        if (opts.path.contains('/api/cas/user')) {
          return ResponseBody.fromString(
            jsonEncode({
              'code': 1,
              'member': {'token': 'TOK'},
            }),
            200,
          );
        }
        return ResponseBody.fromString(
          '<html><form action="authserver"></form></html>',
          200,
        );
      });

    final cas = CasClient(cookieJar: CookieJar(), dio: dio);
    final lib = LibraryService(cas);
    await expectLater(
      lib.member(),
      throwsA(
        isA<AppError>().having(
          (e) => e.kind,
          'kind',
          AppErrorKind.sessionExpired,
        ),
      ),
    );
  });

  testWidgets('SettingsScreen renders master-detail on desktop and switches',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageProvider.overrideWithValue(storage)],
        child: MaterialApp(
          theme: AppTheme.build(brightness: Brightness.light, seed: Colors.teal),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('外观与缩放'), findsOneWidget);
    await tester.tap(find.text('外观与缩放'));
    await tester.pumpAndSettle();
    expect(find.textContaining('界面缩放'), findsOneWidget);
  });

  testWidgets('SettingsScreen renders categorized index on phone (360x640)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storageProvider.overrideWithValue(storage)],
        child: MaterialApp(
          theme: AppTheme.build(brightness: Brightness.light, seed: Colors.teal),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('账号与安全'), findsOneWidget);
    expect(find.text('外观与缩放'), findsOneWidget);
  });
}
