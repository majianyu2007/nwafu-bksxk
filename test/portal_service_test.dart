import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/core/errors.dart';
import 'package:nwafu_bksxk/data/cas_client.dart';
import 'package:nwafu_bksxk/data/portal_service.dart';

import 'support/edu_fixtures.dart';

// Shapes captured from a logged-in browser on 2026-10-13.
const unreadBody = {
  'message': '',
  'result': 'success',
  'data': {
    'wid': 'message',
    'appId': null,
    'cardName': '未读消息',
    'cardSeq': 4,
    'totalSize': 26,
  },
  'hasLogin': true,
  'contextPath': '',
};
const countsBody = {
  'code': 0,
  'message': null,
  'datas': {'todoCount': 0, 'doneCount': 0},
  'title': null,
  'result': 'success',
};
const channelsBody = {
  'errcode': '0',
  'errmsg': '请求成功',
  'data': {
    'configuredChannel': [],
    'subscribedChannel': [
      {'wid': '1997940934735024130', 'name': 'OA通知公告', 'fixed': true},
      {'wid': '1896805772199092226', 'name': '热点聚焦', 'fixed': true},
    ],
  },
};
const newsBody = {
  'errcode': '0',
  'errmsg': '请求成功',
  'data': {
    'datas': {
      'data': [
        {
          'title': '关于招募“红娘团”成员的通知',
          'channelName': 'OA通知公告',
          'columnName': 'OA系统/',
          'pubTime': '2026/10/13',
          'contents': null,
          'abstractVal': null,
          'url': 'https://fwoa.nwafu.edu.cn/docs/docs/DocDspExt.jsp?id=661169',
          'author': '沙影',
          'read': false,
          'enableRead': false,
        },
        {
          'title': '【转载】速递！',
          'channelName': '热点聚焦',
          'pubTime': '2026/10/12',
          'contents': '<p>3月5日上午9时，&nbsp;第十四届</p>',
          'url': 'javascript:alert(1)',
        },
      ],
    },
  },
};
// Unauthenticated answers, checked 2026-10-13.
const jsonpLoggedOut = {
  'message': '',
  'result': 'failed',
  'data': '请登录!',
  'hasLogin': false,
  'contextPath': '',
};

void main() {
  group('PortalItem', () {
    test('ehall news rows', () {
      final rows =
          ((newsBody['data'] as Map)['datas'] as Map)['data'] as List;
      final a = PortalItem.fromRow(rows[0] as Map<String, dynamic>);
      expect(a.title, '关于招募“红娘团”成员的通知');
      expect(a.source, 'OA通知公告');
      expect(a.time, '2026/10/13');
      expect(a.url?.host, 'fwoa.nwafu.edu.cn');
      final b = PortalItem.fromRow(rows[1] as Map<String, dynamic>);
      expect(b.summary, '3月5日上午9时， 第十四届');
      // Non-http links are never opened.
      expect(b.url, isNull);
    });

    test('unknown shapes still show something', () {
      final t = PortalItem.fromRow({
        'TASK_NAME': '学生证补办',
        'NODE_NAME': '学院审核',
        'CREATE_TIME': '2026-10-01 10:00',
        'PC_URL': '/taskcenterapp/detail?id=1',
      }, base: Uri.parse(kNewEhallOrigin));
      expect(t.title, '学生证补办');
      expect(t.summary, '学院审核');
      expect(t.time, '2026-10-01 10:00');
      expect(t.url.toString(), '$kNewEhallOrigin/taskcenterapp/detail?id=1');

      final odd = PortalItem.fromRow({'wid': 'x', 'foo': '一条没有标题字段的消息'});
      expect(odd.title, '一条没有标题字段的消息');
      expect(PortalItem.fromRow({}).title, '（无标题）');
    });

    test('safePortalLink', () {
      expect(safePortalLink('https://a.nwafu.edu.cn/x'), isNotNull);
      expect(safePortalLink('mailto:a@b.c'), isNull);
      expect(safePortalLink('https://u:p@evil.com/'), isNull);
      expect(safePortalLink('/rel'), isNull);
      expect(
        safePortalLink('/rel', base: Uri.parse(kNewEhallOrigin)).toString(),
        '$kNewEhallOrigin/rel',
      );
    });
  });

  group('PortalService', () {
    late EduProtocol protocol;
    late PortalService portal;
    var relogins = 0;

    setUp(() {
      protocol = EduProtocol();
      relogins = 0;
      final dio = Dio(
        BaseOptions(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 500,
        ),
      )..httpClientAdapter = protocol;
      portal = PortalService(CasClient(cookieJar: CookieJar(), dio: dio))
        ..onLoginRequired = () async {
          relogins++;
          return false;
        };
    });

    void casTicket(String origin) {
      protocol
        ..reply(
          'GET',
          '/login',
          '',
          status: 302,
          headers: {
            'location': [
              '$kAuthServer/authserver/login?service=$origin/login',
            ],
          },
        )
        ..reply(
          'GET',
          '/authserver/login',
          '',
          status: 302,
          headers: {
            'location': ['$origin/login?ticket=ST-1'],
          },
        )
        ..reply('GET', '/login', '<html>ok</html>');
    }

    test('inbox: CAS ticket per host, then the read-only endpoints', () async {
      casTicket(kNewEhallOrigin);
      protocol
        ..reply('GET', '/jsonp/ywtb/getUnreadMessageCount', unreadBody)
        ..reply(
          'POST',
          '/taskcenterapp/sys/taskCenter/taskNew/getTaskTodoAndDoneCount.do',
          countsBody,
        )
        ..reply('GET', '/jsonp/getTagsMessages', {
          'result': 'success',
          'data': {
            'count': 1,
            'children': [
              {'title': '成绩已发布', 'sendTime': '2026-10-12'},
            ],
          },
          'hasLogin': true,
        });
      casTicket(kEhallPortalOrigin);
      protocol
        ..add(
          'POST',
          '/execCardMethod/47526598509360696/SYS_CARD_NEWSANNOUNCEMENT',
          (r) {
            final body = jsonDecode(r.data as String) as Map;
            expect(body['method'], 'getConfiguredAndSubscribedChannel');
            return EduProtocol.response(channelsBody);
          },
        )
        ..add(
          'POST',
          '/execCardMethod/47526598509360696/SYS_CARD_NEWSANNOUNCEMENT',
          (r) {
            final body = jsonDecode(r.data as String) as Map;
            expect(body['method'], 'getChannelNews');
            expect(
              (body['param'] as Map)['channelIds'],
              '1997940934735024130,1896805772199092226',
            );
            return EduProtocol.response(newsBody);
          },
        );

      final inbox = await portal.inbox();
      expect(protocol.steps, isEmpty);
      expect(inbox.unread, 26);
      expect(inbox.todo, 0);
      expect(inbox.done, 0);
      expect(inbox.todos, isEmpty);
      expect(inbox.messages.single.title, '成绩已发布');
      expect(inbox.notices.length, 2);
      expect(inbox.errors, isEmpty);
    });

    test('a jsonp "请登录" answer asks for a relogin, then gives up', () async {
      casTicket(kNewEhallOrigin);
      protocol
        ..reply('GET', '/jsonp/ywtb/getUnreadMessageCount', jsonpLoggedOut)
        // hasLogin probe on the AuthServer: no CASTGC.
        ..reply('GET', '/authserver/login', '<input id="execution" value="e">');
      await expectLater(
        portal.unreadCount(),
        throwsA(
          isA<AppError>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.sessionExpired,
          ),
        ),
      );
      expect(relogins, 1);
    });

    test('ticket landing on another host is refused', () async {
      protocol.reply(
        'GET',
        '/login',
        '',
        status: 302,
        headers: {
          'location': ['https://evil.example.com/login'],
        },
      );
      await expectLater(portal.open(PortalHost.newehall), throwsA(isA<AppError>()));
    });
  });
}
