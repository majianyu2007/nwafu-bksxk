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
}
