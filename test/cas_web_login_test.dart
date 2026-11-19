import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/cas_client.dart';

class _WebBridgeAdapter implements HttpClientAdapter {
  _WebBridgeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final calls = <(String, String)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add((options.method, options.uri.toString()));
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _webResp(
  String body, {
  required String finalUrl,
  int status = 200,
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    'x-bksxk-final-url': [finalUrl],
  },
);

void main() {
  const service = 'https://ehall.nwafu.edu.cn/jwapp/sys/wdkbby/*default/index.do';
  const loginHtml = '''
<html><body>
  <form>
    <input type="hidden" name="cllt" value="userNameLogin" />
    <input type="hidden" id="execution" name="execution" value="e1s1" />
    <input type="hidden" id="pwdEncryptSalt" value="1234567890abcdef" />
  </form>
</body></html>
''';
  const mfaHtml = '''
<html><body>
  <input id="username" value="马同学" />
  <div class="reauth-tab-item" data-type="3"></div>
  <script>
    var params = {"reAuthUserId":"2025013665","isMultifactor":"true","service":"$service","pwdEncryptSalt":""};
  </script>
</body></html>
''';

  test('web bridge password login succeeds when GM follows redirects to service',
      () async {
    final adapter = _WebBridgeAdapter((opts) {
      if (opts.uri.path == '/authserver/checkNeedCaptcha.htl') {
        return _webResp(
          jsonEncode({'isNeed': false}),
          finalUrl: opts.uri.toString(),
        );
      }
      if (opts.uri.path == '/authserver/login' && opts.method == 'GET') {
        return _webResp(loginHtml, finalUrl: opts.uri.toString());
      }
      if (opts.uri.path == '/authserver/login' && opts.method == 'POST') {
        return _webResp('<html>ehall</html>', finalUrl: service);
      }
      throw StateError('Unexpected ${opts.method} ${opts.uri}');
    });
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = adapter;
    final cas = CasClient(
      cookieJar: CookieJar(),
      dio: dio,
      webBridgeMode: true,
      casLoginBridgeReady: true,
    );

    await cas.login(service: service, username: '2025013665', password: 'secret');
    expect(adapter.calls.map((c) => c.$1), ['GET', 'GET', 'POST']);
  });

  test('web bridge login handles existing live CASTGC auto-redirect without POST',
      () async {
    final adapter = _WebBridgeAdapter((opts) {
      if (opts.uri.path == '/authserver/login' && opts.method == 'GET') {
        return _webResp('<html>ehall</html>', finalUrl: service);
      }
      throw StateError('Unexpected ${opts.method} ${opts.uri}');
    });
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = adapter;
    final cas = CasClient(
      cookieJar: CookieJar(),
      dio: dio,
      webBridgeMode: true,
      casLoginBridgeReady: true,
    );

    await cas.login(service: service, username: '2025013665', password: 'secret');
    expect(adapter.calls, hasLength(1));
  });

  test('web bridge login surfaces MFA challenge and completes submitMfa',
      () async {
    var mfaDone = false;
    final adapter = _WebBridgeAdapter((opts) {
      if (opts.uri.path == '/authserver/checkNeedCaptcha.htl') {
        return _webResp(jsonEncode({'isNeed': false}), finalUrl: opts.uri.toString());
      }
      if (opts.uri.path == '/authserver/login' && opts.method == 'GET') {
        return _webResp(
          mfaDone ? '<html>ehall</html>' : loginHtml,
          finalUrl: mfaDone ? service : opts.uri.toString(),
        );
      }
      if (opts.uri.path == '/authserver/login' && opts.method == 'POST') {
        return _webResp(
          mfaHtml,
          finalUrl:
              '$kAuthServer/authserver/reAuthCheck/reAuthLoginView.do?isMultifactor=true',
        );
      }
      if (opts.uri.path == '/authserver/bfp/info') {
        return _webResp('', finalUrl: opts.uri.toString());
      }
      if (opts.uri.path == '/authserver/reAuthCheck/reAuthSubmit.do') {
        mfaDone = true;
        return _webResp(
          jsonEncode({'code': 'reAuth_success'}),
          finalUrl: opts.uri.toString(),
        );
      }
      throw StateError('Unexpected ${opts.method} ${opts.uri}');
    });
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = adapter;
    final cas = CasClient(
      cookieJar: CookieJar(),
      dio: dio,
      webBridgeMode: true,
      casLoginBridgeReady: true,
    );

    CasMfaChallenge? challenge;
    try {
      await cas.login(service: service, username: '2025013665', password: 'secret');
    } on CasMfaRequired catch (e) {
      challenge = e.challenge;
    }
    expect(challenge, isNotNull);
    expect(challenge!.methods, [MfaMethod.sms]);

    await cas.submitMfa(challenge, MfaMethod.sms, '123456', trustDevice: true);
    expect(
      adapter.calls.any((c) => c.$2.contains('/authserver/bfp/info')),
      isTrue,
    );
    expect(
      adapter.calls.any((c) => c.$2.contains('/authserver/reAuthCheck/reAuthSubmit.do')),
      isTrue,
    );
  });

  test('web bridge login classifies bad password HTML returned at /authserver/login',
      () async {
    final adapter = _WebBridgeAdapter((opts) {
      if (opts.uri.path == '/authserver/checkNeedCaptcha.htl') {
        return _webResp(jsonEncode({'isNeed': false}), finalUrl: opts.uri.toString());
      }
      if (opts.uri.path == '/authserver/login' && opts.method == 'GET') {
        return _webResp(loginHtml, finalUrl: opts.uri.toString());
      }
      if (opts.uri.path == '/authserver/login' && opts.method == 'POST') {
        return _webResp(
          '<span id="showErrorTip">您提供的用户名或者密码有误</span>',
          finalUrl: opts.uri.toString(),
          status: 401,
        );
      }
      throw StateError('Unexpected ${opts.method} ${opts.uri}');
    });
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = adapter;
    final cas = CasClient(
      cookieJar: CookieJar(),
      dio: dio,
      webBridgeMode: true,
      casLoginBridgeReady: true,
    );

    await expectLater(
      cas.login(service: service, username: '2025013665', password: 'wrong'),
      throwsA(isA<AppError>()
          .having((e) => e.kind, 'kind', AppErrorKind.account)
          .having((e) => e.message, 'message', contains('密码有误'))),
    );
  });

  test('web bridge clearSession and logout call /authserver/logout when 1.5.0+ ready',
      () async {
    final adapter = _WebBridgeAdapter(
      (opts) => _webResp('ok', finalUrl: opts.uri.toString()),
    );
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = adapter;
    final cas = CasClient(
      cookieJar: CookieJar(),
      dio: dio,
      webBridgeMode: true,
      casLoginBridgeReady: true,
    );

    await cas.clearSession();
    await cas.logout();
    expect(
      adapter.calls.where((c) => c.$2 == '$kAuthServer/authserver/logout'),
      hasLength(2),
    );
  });

  test('web bridge login rejects outdated bridge (< 1.5.0) with upgrade hint',
      () async {
    final cas = CasClient(
      cookieJar: CookieJar(),
      dio: Dio(),
      webBridgeMode: true,
      casLoginBridgeReady: false,
    );
    await expectLater(
      cas.login(service: service, username: '2025013665', password: 'secret'),
      throwsA(isA<AppError>()
          .having((e) => e.kind, 'kind', AppErrorKind.schemaOrRedirect)
          .having((e) => e.hint, 'hint', contains('1.5.0'))),
    );
  });

  group('CAS MFA reAuthParams parsing & service normalization', () {
    test('native MFA decodes Thymeleaf escaped slashes in reAuthParams.service',
        () async {
      // Exact escaping observed live on authserver.nwafu.edu.cn (Thymeleaf th:inline="javascript").
      final escapedService = service.replaceAll('/', r'\/');
      final thymeleafMfaHtml = '''
<html><body>
  <input id="username" value="马同学" />
  <div class="reauth-tab-item" data-type="3"></div>
  <script>
    var decoy = {"service": "https:\\/\\/wrong.invalid\\/bad"};
    var contextPath = "\\/authserver";
    var reAuthParams = {
      "isSleepAccount": "0",
      "reAuthType": "3",
      "isMultifactor": "true",
      "service": "$escapedService",
      "reAuthUserId": "2025013665",
      "pwdEncryptSalt": ""
    };
  </script>
</body></html>
''';
      var mfaDone = false;
      String? submittedService;
      String? changeTypeService;
      String? postMfaLoginQueryService;
      final adapter = _WebBridgeAdapter((opts) {
        if (opts.uri.path == '/authserver/checkNeedCaptcha.htl') {
          return ResponseBody.fromString(jsonEncode({'isNeed': false}), 200);
        }
        if (opts.uri.path == '/authserver/login' && opts.method == 'GET') {
          final qsService = opts.uri.queryParameters['service'] ?? '';
          if (qsService.contains(r'\')) {
            return ResponseBody.fromString(
              '<div class="no-access-or-registered-tip">应用未注册</div>',
              200,
            );
          }
          if (mfaDone) {
            postMfaLoginQueryService = qsService;
            return ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['$service?ticket=ST-1'],
              },
            );
          }
          return ResponseBody.fromString(loginHtml, 200);
        }
        if (opts.uri.path == '/authserver/login' && opts.method == 'POST') {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': [
                '/authserver/reAuthCheck/reAuthLoginView.do?isMultifactor=true&service=${Uri.encodeComponent(service)}',
              ],
            },
          );
        }
        if (opts.uri.path == '/authserver/reAuthCheck/reAuthLoginView.do') {
          return ResponseBody.fromString(thymeleafMfaHtml, 200);
        }
        if (opts.uri.path == '/authserver/reAuthCheck/changeReAuthType.do') {
          final form = opts.data as Map;
          changeTypeService = form['service']?.toString();
          return ResponseBody.fromString(
            jsonEncode({
              'code': 1,
              'data': {'reAuthType': '3'},
            }),
            200,
          );
        }
        if (opts.uri.path == '/authserver/dynamicCode/getDynamicCodeByReauth.do') {
          return ResponseBody.fromString(
            jsonEncode({
              'res': 'success',
              'returnMessage': '验证码已发送至',
              'mobile': '138****0000',
            }),
            200,
          );
        }
        if (opts.uri.path == '/authserver/bfp/info') {
          return ResponseBody.fromString('{}', 200);
        }
        if (opts.uri.path == '/authserver/reAuthCheck/reAuthSubmit.do') {
          final form = opts.data as Map;
          submittedService = form['service']?.toString();
          if ((submittedService ?? '').contains(r'\')) {
            return ResponseBody.fromString(
              jsonEncode({'code': 'reAuth_failed', 'msg': '应用未注册'}),
              200,
            );
          }
          mfaDone = true;
          return ResponseBody.fromString(
            jsonEncode({'code': 'reAuth_success'}),
            200,
          );
        }
        if (opts.uri.host == 'ehall.nwafu.edu.cn') {
          if (opts.uri.queryParameters.containsKey('ticket')) {
            return ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': [service],
              },
            );
          }
          return ResponseBody.fromString('<html>ehall</html>', 200);
        }
        throw StateError('Unexpected ${opts.method} ${opts.uri}');
      });

      final dio = Dio(
        BaseOptions(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      )..httpClientAdapter = adapter;
      final cas = CasClient(
        cookieJar: CookieJar(),
        dio: dio,
        webBridgeMode: false,
      );

      CasMfaChallenge? challenge;
      try {
        await cas.login(
          service: service,
          username: '2025013665',
          password: 'secret',
        );
      } on CasMfaRequired catch (e) {
        challenge = e.challenge;
      }
      expect(challenge, isNotNull);
      expect(challenge!.service, service);
      expect(challenge.userId, '2025013665');

      final sentMsg = await cas.sendMfaCode(challenge, MfaMethod.sms);
      expect(sentMsg, contains('138****0000'));
      expect(changeTypeService, service);

      await cas.submitMfa(challenge, MfaMethod.sms, '123456', trustDevice: true);
      expect(submittedService, service);
      expect(postMfaLoginQueryService, service);
    });

    test('parseJsObject handles non-JSON Thymeleaf syntax (\\\', unquoted keys, comments, \\u0026)',
        () {
      const html = r'''
<script>
  var reAuthParams = {
    // comment with } brace
    "reAuthDec3": "Don\'t share <span class=\'tip\'>验证码</span>",
    isSleepAccount: 0,
    reAuthType: '3',
    isMultifactor: true,
    service: 'https:\/\/ehall.nwafu.edu.cn\/jwapp\/sys\/wdkbby\/*default\/index.do?a=1\u0026b=2',
    reAuthUserId: "2025013665",
    pwdEncryptSalt: "abc\/1234567890ef",
  };
</script>
''';
      final obj = CasClient.parseJsObject(html, 'reAuthParams');
      expect(
        obj['service'],
        'https://ehall.nwafu.edu.cn/jwapp/sys/wdkbby/*default/index.do?a=1&b=2',
      );
      expect(obj['reAuthUserId'], '2025013665');
      expect(obj['isMultifactor'], isTrue);
      expect(obj['isSleepAccount'], 0);
      expect(obj['reAuthType'], '3');
      expect(obj['pwdEncryptSalt'], 'abc/1234567890ef');
    });

    test('normalizeCasServiceUrl decodes single-layer percent encoding and rejects invalid/foreign URLs',
        () {
      expect(
        CasClient.normalizeCasServiceUrl(
          'https%3A%2F%2Fehall.nwafu.edu.cn%2Fjwapp%2Fsys%2Fwdkbby%2F*default%2Findex.do',
        ),
        service,
      );
      expect(
        CasClient.normalizeCasServiceUrl(
          r'https:\/\/ehall.nwafu.edu.cn\/jwapp\/sys\/wdkbby\/*default\/index.do',
        ),
        isNull,
      );
      expect(
        CasClient.normalizeCasServiceUrl('https://evil.example.com/login'),
        isNull,
      );
    });

    test('submitMfa surfaces server 应用未注册 and expired redirect clearly', () async {
      final challenge = CasMfaChallenge(
        service: service,
        methods: const [MfaMethod.sms],
        userId: '2025013665',
        displayName: '马同学',
      );

      // 1. JSON error "应用未注册"
      final unregDio = Dio(
        BaseOptions(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      )..httpClientAdapter = _WebBridgeAdapter((opts) {
          if (opts.uri.path == '/authserver/bfp/info') {
            return ResponseBody.fromString('{}', 200);
          }
          return ResponseBody.fromString(
            jsonEncode({'code': 'reAuth_failed', 'msg': '应用未注册'}),
            200,
          );
        });
      final unregCas = CasClient(
        cookieJar: CookieJar(),
        dio: unregDio,
        webBridgeMode: false,
      );
      await expectLater(
        unregCas.submitMfa(challenge, MfaMethod.sms, '123456'),
        throwsA(
          isA<AppError>()
              .having((e) => e.kind, 'kind', AppErrorKind.schemaOrRedirect)
              .having((e) => e.message, 'message', '应用未注册'),
        ),
      );

      // 2. 302 redirect on expired MFA session
      final expiredDio = Dio(
        BaseOptions(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      )..httpClientAdapter = _WebBridgeAdapter((opts) {
          if (opts.uri.path == '/authserver/bfp/info') {
            return ResponseBody.fromString('{}', 200);
          }
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['$kAuthServer/authserver/login'],
            },
          );
        });
      final expiredCas = CasClient(
        cookieJar: CookieJar(),
        dio: expiredDio,
        webBridgeMode: false,
      );
      await expectLater(
        expiredCas.submitMfa(challenge, MfaMethod.sms, '123456'),
        throwsA(
          isA<AppError>()
              .having((e) => e.kind, 'kind', AppErrorKind.sessionExpired)
              .having((e) => e.message, 'message', contains('过期')),
        ),
      );

      // 3. classifyLoginFailure extracts live 应用未注册 HTML page
      final htmlErr = classifyLoginFailure(
        '<html><title>应用未注册</title><div class="no-access-or-registered-tip">应用未注册</div></html>',
      );
      expect(htmlErr.kind, AppErrorKind.schemaOrRedirect);
      expect(htmlErr.message, '应用未注册');
    });
  });
}
