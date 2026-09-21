import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/auth_service.dart';
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
}
