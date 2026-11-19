import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/auth_service.dart';
import 'package:nwafu_bksxk/data/captcha.dart';
import 'package:nwafu_bksxk/data/models.dart';

class ContextClient extends ApiClient {
  ContextClient() : super(origin: 'http://localhost');
  Map<String, dynamic> profile = {
    'code': 'STUDENT',
    'name': '同学',
    'campus': '01',
    'electiveBatchList': [
      {
        'code': 'NOW',
        'name': '当前轮次',
        'canSelect': '1',
        'needConfirm': '1',
        'isConfirmed': '0'
      }
    ],
    'expElectiveBatchList': [],
  };
  String profileCode = '1';
  int contextLoads = 0;
  @override
  Future<ApiResult> getJson(String path,
      {Map<String, dynamic>? query,
      bool auth = true,
      bool addTimestamp = true,
      bool allowRelogin = true}) async {
    if (path == Api.studentInfo('STUDENT')) {
      contextLoads++;
      return ApiResult.fromJson(
          {'code': profileCode, 'msg': '学籍信息不可用', 'data': profile});
    }
    if (path == Api.batch) {
      return ApiResult.fromJson({
        'code': '1',
        'dataList': [
          if (contextLoads == 1)
            for (var i = 1; i <= 3; i++)
              {'code': 'OLD$i', 'name': '已过期小课程申请$i', 'canSelect': '1'},
          {
            'code': 'NOW',
            'name': '公共名称',
            'canSelect': '0',
            'needConfirm': '0',
            'isConfirmed': '1',
            'displayXGXK': '0'
          },
        ]
      });
    }
    throw StateError('Unexpected path $path');
  }
}

void main() {
  test(
      'first context excludes public historical rounds just like later contexts',
      () async {
    final auth = AuthService(ContextClient());
    final (_, first) = await auth.loadContext('STUDENT');
    final (_, second) = await auth.loadContext('STUDENT');
    expect(first.map((b) => b.code), ['NOW']);
    expect(second.map((b) => b.code), ['NOW']);
    expect(selectInitialBatch(first).batch?.code, 'NOW');
    expect(first.single.canSelect, isTrue);
    expect(first.single.needsNoticeConfirmation, isTrue);
    expect(first.single.showsKind(CourseKind.xgxk), isFalse);
  });
  test('empty student lists cannot become historical public rounds', () async {
    final client = ContextClient()..profile['electiveBatchList'] = [];
    final (_, rounds) = await AuthService(client).loadContext('STUDENT');
    expect(rounds, isEmpty);
  });
  test('failed profile cannot be promoted to a logged-in context', () async {
    final client = ContextClient()..profileCode = '2';
    await expectLater(
        AuthService(client).loadContext('STUDENT'),
        throwsA(isA<AppError>()
            .having((e) => e.kind, 'kind', AppErrorKind.businessRejected)));
  });
  test('missing student round fields is invalid rather than public fallback',
      () async {
    final client = ContextClient()..profile = {'code': 'STUDENT'};
    await expectLater(
        AuthService(client).loadContext('STUDENT'),
        throwsA(isA<AppError>()
            .having((e) => e.kind, 'kind', AppErrorKind.schemaOrRedirect)));
  });
  test('experimental rounds remain profile-owned and duplicate ids appear once',
      () {
    final rounds = mergeBatchAvailability([], {
      'electiveBatchList': [
        {'code': 'N', 'canSelect': '0'}
      ],
      'expElectiveBatchList': [
        {'code': 'E', 'canSelect': '1'},
        {'code': 'E'},
        {'code': ''}
      ],
    });
    expect(rounds.map((b) => b.code), ['N', 'E']);
    expect(rounds.last.canSelect, isTrue);
  });
  test('public eligibility and stale refusal never supply student state', () {
    final rounds = mergeBatchAvailability([
      {
        'code': 'N',
        'canSelect': '1',
        'noSelectReason': '过期原因',
        'isConfirmed': '1'
      },
    ], {
      'electiveBatchList': [
        {'code': 'N', 'noSelectReason': null, 'needConfirm': '1'},
      ],
    });
    expect(rounds.single.canSelect, isFalse);
    expect(rounds.single.noSelectReason, isEmpty);
    expect(rounds.single.needsNoticeConfirmation, isTrue);
  });

  group('cluster stale-node detection & recovery', () {
    setUp(ApiClient.resetClusterNodeCache);
    tearDown(ApiClient.resetClusterNodeCache);

    final sepRounds = [
      ElectiveBatch(
        code: '36a0648e',
        name: '2026年秋季学期形势与政策（补选）',
        batchType: '01',
        canSelect: false,
        beginTime: '2026-09-09 09:00:00',
        endTime: '2026-09-15 18:00:00',
        noSelectReason: '不在选课轮次范围内',
      ),
      ElectiveBatch(
        code: 'da2f7dd9',
        name: '2026年秋季学期网上补选',
        batchType: '01',
        canSelect: false,
        beginTime: '2026-09-09 09:00:00',
        endTime: '2026-09-11 18:00:00',
        noSelectReason: '不在选课轮次范围内',
      ),
    ];
    final octRounds = [
      ElectiveBatch(
        code: 'a9f96359',
        name: '2026年秋季学期本科课程重修选课',
        batchType: '01',
        canSelect: false,
        beginTime: '2026-10-08 09:00:00',
        endTime: '2026-10-16 18:00:00',
        noSelectReason: '不在选课轮次范围内',
      ),
    ];

    test('looksLikeStaleRoundSnapshot catches lagging initTimestamp', () {
      expect(
        looksLikeStaleRoundSnapshot(
          studentBatches: sepRounds,
          publicBatches: sepRounds,
          nodeInitTimestamp: 1788928141330,
          knownClusterInitTimestamp: 1792144680028,
        ),
        isTrue,
      );
    });

    test('looksLikeStaleRoundSnapshot catches disjoint older student rounds',
        () {
      expect(
        looksLikeStaleRoundSnapshot(
          studentBatches: sepRounds,
          publicBatches: octRounds,
        ),
        isTrue,
      );
    });

    test('looksLikeStaleRoundSnapshot allows matching off-season rounds', () {
      expect(
        looksLikeStaleRoundSnapshot(
          studentBatches: octRounds,
          publicBatches: octRounds,
          nodeInitTimestamp: 1792144680028,
          knownClusterInitTimestamp: 1792144680028,
        ),
        isFalse,
      );
    });

    test('looksLikeStaleRoundSnapshot ignores experimental-only student rounds',
        () {
      final expOnly = [
        ElectiveBatch(
          code: 'EXP1',
          name: '实验选课',
          batchType: '02',
          canSelect: false,
          beginTime: '2026-09-09 09:00:00',
          endTime: '2026-09-11 18:00:00',
        ),
      ];
      expect(
        looksLikeStaleRoundSnapshot(
          studentBatches: expOnly,
          publicBatches: octRounds,
        ),
        isFalse,
      );
    });

    test('pinFreshNode selects highest initTimestamp, pins cookie, and caches',
        () async {
      final client = _ClusterClient([
        const ClusterNodeProbe(
            route: '2074c2538aee3dfbb37bbf24e6596c51',
            initTimestamp: 1788928141330),
        const ClusterNodeProbe(
            route: 'f5a676915751f478db3c4448bd0d8db3',
            initTimestamp: 1792144680028),
        const ClusterNodeProbe(
            route: '622503b5c3b661d3018e64339e65752b',
            initTimestamp: 1792144680028),
      ]);
      final chosen = await client.pinFreshNode();
      expect(chosen?.route, 'f5a676915751f478db3c4448bd0d8db3');
      expect(chosen?.initTimestamp, 1792144680028);
      expect(await client.currentRouteCookie(),
          'f5a676915751f478db3c4448bd0d8db3');
      final sentCookies = await client.cookieJar.loadForRequest(
        Uri.parse('https://cluster.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/check/login.do'),
      );
      expect(
        sentCookies.any((c) =>
            c.name == 'route' && c.value == 'f5a676915751f478db3c4448bd0d8db3'),
        isTrue,
      );
      expect(client.probeCalls, 3);

      // A second client for the same origin reuses the verified-fresh node.
      final second = _ClusterClient(const []);
      final cached = await second.pinFreshNode();
      expect(cached?.route, 'f5a676915751f478db3c4448bd0d8db3');
      expect(second.probeCalls, 0);
      expect(await second.currentRouteCookie(),
          'f5a676915751f478db3c4448bd0d8db3');

      // forceRefresh rotates away from the previously pinned route.
      final rotated = await client.pinFreshNode(forceRefresh: true);
      expect(rotated?.route, '622503b5c3b661d3018e64339e65752b');
      expect(await client.currentRouteCookie(),
          '622503b5c3b661d3018e64339e65752b');
    });

    test('loginInteractive recovers automatically from a lagging zombie node',
        () async {
      final client = _ZombieRecoveryClient();
      final auth = AuthService(client);
      final mgr = SessionManager(
        client: client,
        auth: auth,
        solver: OcrCaptchaSolver((_) async => 'abcd'),
      );

      await mgr.loginInteractive(
        loginName: '2025013665',
        password: 'pw',
        verifyCode: '1234',
        vtoken: 'vt1',
      );

      expect(client.forcePinCalls, 1);
      expect(client.loginCalls, 1,
          reason: 'rotating route recovers fresh rounds without re-login');
      expect(mgr.batches.map((b) => b.code), ['a9f96359']);
      expect(mgr.activeBatch?.code, 'a9f96359');
    });

    test(
        'loginInteractive silently re-logs in once when cold first login returns stale historical rounds on a fresh node',
        () async {
      final client = _ColdFirstLoginStaleClient();
      final auth = AuthService(client);
      final mgr = SessionManager(
        client: client,
        auth: auth,
        solver: OcrCaptchaSolver((_) async => 'abcd'),
      );

      await mgr.loginInteractive(
        loginName: '2025013665',
        password: 'pw',
        verifyCode: '1234',
        vtoken: 'vt1',
      );

      expect(client.loginCalls, 2,
          reason: 'first login saw stale Sep-9 rounds; automatic relogin fixed it');
      expect(mgr.batches.map((b) => b.code), ['a9f96359']);
      expect(mgr.activeBatch?.canSelect, isTrue);
    });

    test('logout sends auth token header matching official site', () async {
      final client = _LogoutRecordingClient()..token = 'live-tok';
      await AuthService(client).logout('2025013665');
      expect(client.logoutAuthFlag, isTrue);
      expect(client.token, isNull);
    });
  });
}

class _ClusterClient extends ApiClient {
  _ClusterClient(this._probes) : super(origin: 'https://cluster.nwafu.edu.cn');

  final List<ClusterNodeProbe> _probes;
  int probeCalls = 0;

  @override
  bool get supportsClusterProbe => true;

  @override
  Future<ClusterNodeProbe?> probeCookielessNode() async {
    final idx = probeCalls++;
    if (_probes.isEmpty) return null;
    return _probes[idx % _probes.length];
  }
}

class _ZombieRecoveryClient extends ApiClient {
  _ZombieRecoveryClient() : super(origin: 'https://zombie.nwafu.edu.cn');

  bool onFreshNode = false;
  int forcePinCalls = 0;
  int loginCalls = 0;

  @override
  bool get supportsClusterProbe => true;

  @override
  Future<ClusterNodeProbe?> pinFreshNode({
    bool forceRefresh = false,
    int probes = 3,
  }) async {
    recordClusterInitTimestamp(1792144680028);
    if (forceRefresh) {
      forcePinCalls++;
      onFreshNode = true;
      return const ClusterNodeProbe(
        route: 'f5a676915751f478db3c4448bd0d8db3',
        initTimestamp: 1792144680028,
      );
    }
    return const ClusterNodeProbe(
      route: '2074c2538aee3dfbb37bbf24e6596c51',
      initTimestamp: 1788928141330,
    );
  }

  @override
  Future<int?> fetchCurrentNodeInitTimestamp() async =>
      onFreshNode ? 1792144680028 : 1788928141330;

  @override
  Future<ApiResult> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
    bool addTimestamp = true,
    bool allowRelogin = true,
  }) async {
    if (path == Api.checkLogin) {
      loginCalls++;
      return ApiResult.fromJson({
        'code': '1',
        'data': {'token': 'tok-$loginCalls', 'number': '2025013665'},
      });
    }
    if (path == Api.studentInfo('2025013665')) {
      return ApiResult.fromJson({
        'code': '1',
        'data': {
          'code': '2025013665',
          'name': '测试同学',
          'campus': '01',
          'electiveBatchList': onFreshNode
              ? [
                  {
                    'code': 'a9f96359',
                    'name': '2026年秋季学期本科课程重修选课',
                    'batchType': '01',
                    'beginTime': '2026-10-08 09:00:00',
                    'endTime': '2026-10-16 18:00:00',
                    'canSelect': '0',
                  },
                ]
              : [
                  {
                    'code': '36a0648e',
                    'name': '2026年秋季学期形势与政策（补选）',
                    'batchType': '01',
                    'beginTime': '2026-09-09 09:00:00',
                    'endTime': '2026-09-15 18:00:00',
                    'canSelect': '0',
                  },
                ],
          'expElectiveBatchList': [],
        },
      });
    }
    if (path == Api.batch) {
      return ApiResult.fromJson({
        'code': '1',
        'dataList': onFreshNode
            ? [
                {
                  'code': 'a9f96359',
                  'name': '2026年秋季学期本科课程重修选课',
                  'batchType': '01',
                  'beginTime': '2026-10-08 09:00:00',
                  'endTime': '2026-10-16 18:00:00',
                },
              ]
            : [
                {
                  'code': '36a0648e',
                  'name': '2026年秋季学期形势与政策（补选）',
                  'batchType': '01',
                  'beginTime': '2026-09-09 09:00:00',
                  'endTime': '2026-09-15 18:00:00',
                },
              ],
      });
    }
    throw StateError('Unexpected path $path');
  }
}

class _ColdFirstLoginStaleClient extends ApiClient {
  _ColdFirstLoginStaleClient() : super(origin: 'https://cold.nwafu.edu.cn');

  int loginCalls = 0;

  @override
  bool get supportsClusterProbe => true;

  @override
  Future<ClusterNodeProbe?> pinFreshNode({
    bool forceRefresh = false,
    int probes = 3,
  }) async {
    recordClusterInitTimestamp(1792144680028);
    return const ClusterNodeProbe(
      route: 'f5a676915751f478db3c4448bd0d8db3',
      initTimestamp: 1792144680028,
    );
  }

  @override
  Future<int?> fetchCurrentNodeInitTimestamp() async => 1792144680028;

  @override
  Future<List<int>> getBytes(String path,
          {Map<String, dynamic>? query, bool auth = false}) async =>
      const [1, 2, 3];

  @override
  Future<ApiResult> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
    bool addTimestamp = true,
    bool allowRelogin = true,
  }) async {
    if (path == Api.vcodeToken) {
      return ApiResult.fromJson({
        'code': '1',
        'data': {'token': 'vt-next'},
      });
    }
    if (path == Api.checkLogin) {
      loginCalls++;
      return ApiResult.fromJson({
        'code': '1',
        'data': {'token': 'tok-$loginCalls', 'number': '2025013665'},
      });
    }
    if (path == Api.studentInfo('2025013665')) {
      return ApiResult.fromJson({
        'code': '1',
        'data': {
          'code': '2025013665',
          'name': '测试同学',
          'campus': '01',
          // First login returns the 3 stale Sep-9 rounds; second login returns fresh Oct round.
          'electiveBatchList': loginCalls <= 1
              ? [
                  {
                    'code': '36a0648e',
                    'name': '2026年秋季学期形势与政策（补选）',
                    'batchType': '01',
                    'beginTime': '2026-09-09 09:00:00',
                    'endTime': '2026-09-15 18:00:00',
                    'canSelect': '0',
                  },
                ]
              : [
                  {
                    'code': 'a9f96359',
                    'name': '2026年秋季学期本科课程重修选课',
                    'batchType': '01',
                    'beginTime': '2026-10-08 09:00:00',
                    'endTime': '2026-10-16 18:00:00',
                    'canSelect': '1',
                  },
                ],
          'expElectiveBatchList': [],
        },
      });
    }
    if (path == Api.batch) {
      return ApiResult.fromJson({
        'code': '1',
        'dataList': [
          {
            'code': 'a9f96359',
            'name': '2026年秋季学期本科课程重修选课',
            'batchType': '01',
            'beginTime': '2026-10-08 09:00:00',
            'endTime': '2026-10-16 18:00:00',
          },
        ],
      });
    }
    throw StateError('Unexpected path $path');
  }
}

class _LogoutRecordingClient extends ApiClient {
  _LogoutRecordingClient() : super(origin: 'http://localhost');

  bool? logoutAuthFlag;

  @override
  Future<ApiResult> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
    bool addTimestamp = true,
    bool allowRelogin = true,
  }) async {
    if (path == Api.logout) {
      logoutAuthFlag = auth;
      return ApiResult.fromJson({'code': '1', 'msg': 'ok'});
    }
    throw StateError('Unexpected path $path');
  }
}
