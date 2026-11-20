import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/cas_client.dart';
import 'package:nwafu_bksxk/data/ehall_service.dart';
import 'package:nwafu_bksxk/data/library_service.dart';
import 'package:nwafu_bksxk/data/portal_service.dart';
import 'package:nwafu_bksxk/data/secure_cookie_storage.dart';

import 'support/edu_fixtures.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);
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
  group('SafePersistCookieJar & OriginScopedCookieManager', () {
    test(
      'cold-start library CAS redirect with PHPSESSID preserves persisted CASTGC and fingerprint',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = MemoryEduStorage(await SharedPreferences.getInstance());
        const accountId = '2025013665';

        // Session 1: login persists CASTGC and MULTIFACTOR_BROWSER_FINGERPRINT
        // on authserver.nwafu.edu.cn (via a 302 redirect to ehall).
        {
          final cookieStorage = SecureCookieStorage(storage, accountId);
          final jar = SafePersistCookieJar(storage: cookieStorage);
          final dio = Dio(
            BaseOptions(
              responseType: ResponseType.plain,
              followRedirects: false,
              validateStatus: (s) => s != null && s < 500,
            ),
          )..httpClientAdapter = _ScriptedAdapter((opts) {
              if (opts.uri.host == 'authserver.nwafu.edu.cn') {
                return ResponseBody.fromString(
                  '',
                  302,
                  headers: {
                    'set-cookie': [
                      'CASTGC=TGT-LIVE-1; Path=/authserver/; Secure; HttpOnly',
                      'MULTIFACTOR_BROWSER_FINGERPRINT=FP-TRUSTED-1; Max-Age=2147483647; Expires=Wed, 08 Dec 2094 03:39:01 GMT; Path=/; HttpOnly',
                    ],
                    'location': [
                      'https://ehall.nwafu.edu.cn/jwapp/sys/wdkbby/*default/index.do?ticket=ST-1',
                    ],
                  },
                );
              }
              return ResponseBody.fromString('<html>ehall</html>', 200);
            });
          final cas = CasClient(
            cookieJar: jar,
            dio: dio,
            webBridgeMode: false,
          );
          await cas.follow(
            'https://authserver.nwafu.edu.cn/authserver/login?service=https%3A%2F%2Fehall.nwafu.edu.cn%2Fjwapp%2Fsys%2Fwdkbby%2F*default%2Findex.do',
          );

          // RFC 6265: authserver's CASTGC must never leak into ehall's jar.
          final ehallCookies = await jar.loadForRequest(
            Uri.parse('https://ehall.nwafu.edu.cn/authserver/login'),
          );
          expect(ehallCookies.where((c) => c.name == 'CASTGC'), isEmpty);
          await cookieStorage.close();
        }

        // Session 2 (cold start): fresh SafePersistCookieJar opens booking-lib
        // FIRST before authserver has ever been read in this process.
        // booking-lib responds 302 with Set-Cookie: PHPSESSID + Location: authserver.
        {
          final cookieStorage = SecureCookieStorage(storage, accountId);
          final jar = SafePersistCookieJar(storage: cookieStorage);
          String? cookieSentToAuthServer;
          String? cookieSentToLibWithTicket;

          final dio = Dio(
            BaseOptions(
              responseType: ResponseType.plain,
              followRedirects: false,
              validateStatus: (s) => s != null && s < 500,
            ),
          )..httpClientAdapter = _ScriptedAdapter((opts) {
              if (opts.uri.host == 'booking-lib.nwafu.edu.cn' &&
                  opts.uri.path == '/api/cas/cas') {
                if (opts.uri.queryParameters['ticket'] == 'ST-LIB-1') {
                  cookieSentToLibWithTicket =
                      opts.headers['cookie']?.toString();
                  return ResponseBody.fromString(
                    '',
                    302,
                    headers: {
                      'set-cookie': ['PHPSESSID=PHP-AUTHED; path=/'],
                      'location': [
                        'https://booking-lib.nwafu.edu.cn/h5/index.html#/cas/?cas=LIBCODE1',
                      ],
                    },
                  );
                }
                return ResponseBody.fromString(
                  '',
                  302,
                  headers: {
                    'set-cookie': ['PHPSESSID=PHP-INIT; path=/'],
                    'location': [
                      'https://authserver.nwafu.edu.cn/authserver/login?service=https%3A%2F%2Fbooking-lib.nwafu.edu.cn%2Fapi%2Fcas%2Fcas',
                    ],
                  },
                );
              }
              if (opts.uri.host == 'authserver.nwafu.edu.cn' &&
                  opts.uri.path == '/authserver/login') {
                cookieSentToAuthServer = opts.headers['cookie']?.toString();
                if ((cookieSentToAuthServer ?? '').contains('CASTGC=TGT-LIVE-1')) {
                  return ResponseBody.fromString(
                    '',
                    302,
                    headers: {
                      'location': [
                        'https://booking-lib.nwafu.edu.cn/api/cas/cas?ticket=ST-LIB-1',
                      ],
                    },
                  );
                }
                return ResponseBody.fromString('<html>login</html>', 200);
              }
              if (opts.uri.path == '/h5/index.html') {
                return ResponseBody.fromString('<html>h5</html>', 200);
              }
              if (opts.uri.path == '/api/cas/user') {
                return ResponseBody.fromString(
                  jsonEncode({
                    'code': 1,
                    'member': {'token': 'LIB-TOK-1'},
                  }),
                  200,
                );
              }
              if (opts.uri.path == '/api/Member/my') {
                return ResponseBody.fromString(
                  jsonEncode({
                    'code': 1,
                    'data': {'name': '测试同学', 'roleName': '本科生'},
                  }),
                  200,
                );
              }
              throw StateError('Unexpected ${opts.method} ${opts.uri}');
            });

          final cas = CasClient(
            cookieJar: jar,
            dio: dio,
            webBridgeMode: false,
          );
          final lib = LibraryService(cas);
          final member = await lib.member();

          expect(member.name, '测试同学');
          expect(cookieSentToAuthServer, contains('CASTGC=TGT-LIVE-1'));
          expect(
            cookieSentToAuthServer,
            contains('MULTIFACTOR_BROWSER_FINGERPRINT=FP-TRUSTED-1'),
          );
          expect(cookieSentToAuthServer, isNot(contains('PHPSESSID')));
          expect(cookieSentToLibWithTicket, contains('PHPSESSID=PHP-INIT'));
          await cookieStorage.close();
        }
      },
    );

    test(
      'SafePersistCookieJar hydrates existing host cookies before direct saveFromResponse',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = MemoryEduStorage(await SharedPreferences.getInstance());
        const accountId = '2025013665';
        final authUri = Uri.parse('https://authserver.nwafu.edu.cn/authserver/login');

        {
          final cs = SecureCookieStorage(storage, accountId);
          final jar = SafePersistCookieJar(storage: cs);
          await jar.saveFromResponse(authUri, [
            Cookie.fromSetCookieValue('CASTGC=TGT-KEEP; Path=/authserver/; Secure; HttpOnly'),
          ]);
          await cs.close();
        }

        // Cold start: call saveFromResponse on authserver BEFORE any loadForRequest.
        {
          final cs = SecureCookieStorage(storage, accountId);
          final jar = SafePersistCookieJar(storage: cs);
          await jar.saveFromResponse(authUri, [
            Cookie.fromSetCookieValue('route=NODE2; Path=/authserver'),
          ]);
          final cookies = await jar.loadForRequest(authUri);
          expect(cookies.map((c) => c.name), containsAll(['CASTGC', 'route']));
          await cs.close();
        }
      },
    );

    test(
      'OriginScopedCookieManager preserves Expires dates in comma-joined Set-Cookie and merges Cookie case-insensitively',
      () async {
        final jar = CookieJar();
        String? capturedCookie;
        int cookieHeaderKeys = 0;

        final dio = Dio(BaseOptions(responseType: ResponseType.plain))
          ..interceptors.add(OriginScopedCookieManager(jar))
          ..httpClientAdapter = _ScriptedAdapter((opts) {
            if (opts.uri.path == '/set') {
              return ResponseBody.fromString(
                'ok',
                200,
                headers: {
                  'set-cookie': [
                    'MULTIFACTOR_BROWSER_FINGERPRINT=FP-1; Max-Age=2147483647; Expires=Fri, 08-Dec-2094 03:54:48 GMT; Path=/; HttpOnly, CASTGC=TGT-9; Path=/; Secure',
                  ],
                },
              );
            }
            cookieHeaderKeys = opts.headers.keys
                .where((k) => k.toLowerCase() == 'cookie')
                .length;
            capturedCookie = opts.headers['cookie']?.toString();
            return ResponseBody.fromString('ok', 200);
          });

        await dio.get<String>('https://authserver.nwafu.edu.cn/set');
        await dio.get<String>(
          'https://authserver.nwafu.edu.cn/check',
          options: Options(headers: {'Cookie': 'custom=1'}),
        );

        expect(cookieHeaderKeys, 1);
        expect(capturedCookie, contains('MULTIFACTOR_BROWSER_FINGERPRINT=FP-1'));
        expect(capturedCookie, contains('CASTGC=TGT-9'));
        expect(capturedCookie, contains('custom=1'));
      },
    );
  });

  group('LibraryService AuthServer error & MFA handling', () {
    test(
      'reAuthCheck redirect reports MFA guidance without invoking silentRelogin',
      () async {
        var reloginCalls = 0;
        final dio = Dio(
          BaseOptions(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
          ),
        )..httpClientAdapter = _ScriptedAdapter((opts) {
            if (opts.uri.host == 'booking-lib.nwafu.edu.cn') {
              return ResponseBody.fromString(
                '',
                302,
                headers: {
                  'set-cookie': ['PHPSESSID=P1; path=/'],
                  'location': [
                    'https://authserver.nwafu.edu.cn/authserver/login?service=https%3A%2F%2Fbooking-lib.nwafu.edu.cn%2Fapi%2Fcas%2Fcas',
                  ],
                },
              );
            }
            if (opts.uri.path == '/authserver/login') {
              return ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': [
                    'https://authserver.nwafu.edu.cn/authserver/reAuthCheck/reAuthLoginView.do?isMultifactor=true',
                  ],
                },
              );
            }
            return ResponseBody.fromString('<html>reAuth</html>', 200);
          });

        final cas = CasClient(
          cookieJar: CookieJar(),
          dio: dio,
          webBridgeMode: false,
        );
        final lib = LibraryService(
          cas,
          onLoginRequired: () async {
            reloginCalls++;
            return false;
          },
        );

        await expectLater(
          lib.member(),
          throwsA(
            isA<AppError>()
                .having((e) => e.kind, 'kind', AppErrorKind.sessionExpired)
                .having((e) => e.message, 'message', contains('二次验证'))
                .having((e) => e.hint, 'hint', contains('信任此设备')),
          ),
        );
        expect(reloginCalls, 0);
      },
    );

    test(
      'clean login HTML with empty formErrorTip triggers silentRelogin instead of false error tip',
      () async {
        // Exact markup observed live on authserver.nwafu.edu.cn where an empty
        // formErrorTip div is followed later in the page by <span>7天免登录</span>.
        const cleanLoginHtml = '''
<html><body>
  <div id="formErrorTip" class="form-errorTip">
    <span id="showErrorTip" class="form-error"></span>
    <span id="showWarnTip" class="form-warn"></span>&nbsp;
  </div>
  <label><input type="checkbox" name="rememberMe" /><span>7天免登录</span></label>
</body></html>
''';
        expect(extractCasErrorTip(cleanLoginHtml), isEmpty);

        var reloginCalls = 0;
        final dio = Dio(
          BaseOptions(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
          ),
        )..httpClientAdapter = _ScriptedAdapter((opts) {
            if (opts.uri.host == 'booking-lib.nwafu.edu.cn') {
              return ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': [
                    'https://authserver.nwafu.edu.cn/authserver/login?service=https%3A%2F%2Fbooking-lib.nwafu.edu.cn%2Fapi%2Fcas%2Fcas',
                  ],
                },
              );
            }
            return ResponseBody.fromString(cleanLoginHtml, 200);
          });

        final cas = CasClient(
          cookieJar: CookieJar(),
          dio: dio,
          webBridgeMode: false,
        );
        final lib = LibraryService(
          cas,
          onLoginRequired: () async {
            reloginCalls++;
            return false;
          },
        );

        await expectLater(
          lib.member(),
          throwsA(
            isA<AppError>()
                .having((e) => e.kind, 'kind', AppErrorKind.sessionExpired)
                .having((e) => e.message, 'message', '统一身份认证未登录或已过期'),
          ),
        );
        expect(reloginCalls, 1);
      },
    );
  });

  group('EhallService & PortalService reAuthCheck handling', () {
    test(
      'EhallService and PortalService surface MFA guidance on reAuthCheck without invoking silentRelogin',
      () async {
        var reloginCalls = 0;
        final dio = Dio(
          BaseOptions(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
          ),
        )..httpClientAdapter = _ScriptedAdapter((opts) {
            if (opts.uri.host == 'ehall.nwafu.edu.cn' ||
                opts.uri.host == 'newehall.nwafu.edu.cn') {
              return ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': [
                    'https://authserver.nwafu.edu.cn/authserver/login?service=${Uri.encodeComponent(opts.uri.toString())}',
                  ],
                },
              );
            }
            if (opts.uri.path == '/authserver/login') {
              return ResponseBody.fromString(
                '',
                302,
                headers: {
                  'location': [
                    'https://authserver.nwafu.edu.cn/authserver/reAuthCheck/reAuthLoginView.do?isMultifactor=true',
                  ],
                },
              );
            }
            return ResponseBody.fromString('<html>reAuth</html>', 200);
          });

        final cas = CasClient(
          cookieJar: CookieJar(),
          dio: dio,
          webBridgeMode: false,
        );
        final ehall = EhallService(cas)
          ..onLoginRequired = () async {
            reloginCalls++;
            return false;
          };
        final portal = PortalService(cas)
          ..onLoginRequired = () async {
            reloginCalls++;
            return false;
          };

        await expectLater(
          ehall.currentTerm(),
          throwsA(
            isA<AppError>()
                .having((e) => e.kind, 'kind', AppErrorKind.sessionExpired)
                .having((e) => e.message, 'message', contains('二次验证'))
                .having((e) => e.hint, 'hint', contains('信任此设备')),
          ),
        );
        await expectLater(
          portal.unreadCount(),
          throwsA(
            isA<AppError>()
                .having((e) => e.kind, 'kind', AppErrorKind.sessionExpired)
                .having((e) => e.message, 'message', contains('二次验证'))
                .having((e) => e.hint, 'hint', contains('信任此设备')),
          ),
        );
        expect(reloginCalls, 0);
      },
    );
  });
}
