import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/cas_client.dart';
import 'package:nwafu_bksxk/data/degree_audit.dart';
import 'package:nwafu_bksxk/data/ehall_service.dart';

import 'support/edu_fixtures.dart';

/// Responses captured from 学业完成查询 on 2026-10-13 (names/ids redacted).
/// The cxscfakz capture was cut short, so it holds its first four rows.
final Map<String, dynamic> live = jsonDecode(
  File('test/fixtures/degree_audit_live.json').readAsStringSync(),
);

List<Map<String, dynamic>> rowsOf(String name) =>
    ((live[name]['datas'] as Map)[name]['rows'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  group('parsers', () {
    test('a live group row', () {
      final g = DegreeGroup.fromRow(rowsOf('cxscfakz').first);
      expect(g.id, '0046e45abf1a45008f0767bf18bc51a8');
      expect(g.isRoot, isTrue);
      expect(g.name, '综合实践');
      expect(g.nature, '必修');
      expect(g.earned, 5);
      expect(g.goal, 29);
      expect(g.missing, 24);
      expect(g.short, isTrue);
      expect(g.openCourses, 3);
      expect(g.kind, '01');
    });

    test('a passed group with zero requirement is never short', () {
      final row = rowsOf('cxscfakz').firstWhere((r) => r['SFTG'] == '1');
      final g = DegreeGroup.fromRow(row);
      expect(g.goal, 0);
      expect(g.passed, isTrue);
      expect(g.short, isFalse);
      expect(g.progress, 1);
    });

    test('plan from the live rows', () {
      final plan = DegreePlan.fromRows(
        plan: rowsOf('grpyfacx').single,
        audit: rowsOf('cxscfa').single,
        groups: rowsOf('cxscfakz'),
        selected: selectedCreditsFrom(
          (live['cxfakzyxxfgj'][''] as Map)['datas']['cxfakzyxxfgj']['rows']
              .cast<Map<String, dynamic>>(),
        ),
      );
      expect(plan.name, '2025级软件工程主修培养方案');
      expect(plan.kind, '主修');
      // The audit row wins over grpyfacx's stale YWCXF (1.0).
      expect(plan.earned, 51);
      expect(plan.goal, 155);
      expect(plan.missing, 104);
      expect(plan.selected, 28);
      expect(plan.computedAt, '2026-10-08 16:42:43');
      // Groups whose parent is not in the (truncated) list sit at the top.
      expect(plan.groups.map((g) => g.name), contains('综合实践'));
      expect(plan.allGroups.length, 4);
    });

    test('tree: children under parents, BZ order, orphans and cycles', () {
      DegreeGroup g(String id, String parent, {int order = 1}) => DegreeGroup(
        id: id,
        parentId: parent,
        name: id,
        order: order,
      );
      final tree = buildDegreeTree([
        g('b', '-1', order: 2),
        g('a', '-1', order: 1),
        g('a2', 'a', order: 2),
        g('a1', 'a', order: 1),
        g('orphan', 'missing'),
        g('x', 'y'),
        g('y', 'x'),
      ]);
      expect(tree.map((e) => e.id), ['a', 'orphan', 'b']);
      expect(tree.first.children.map((e) => e.id), ['a1', 'a2']);
      // x and y only point at each other: neither is reachable from the top
      // level, and building must still terminate.
      expect(tree.expand((e) => e.children).length, 2);
    });

    test('shortLeaves names the deepest groups still short', () {
      final plan = DegreePlan(
        id: 'p',
        name: 'p',
        goal: 10,
        earned: 4,
        groups: buildDegreeTree([
          DegreeGroup(id: 'r', parentId: '-1', name: '必修', goal: 6, earned: 2),
          DegreeGroup(id: 'c', parentId: 'r', name: '数学', goal: 4, earned: 0),
          DegreeGroup(id: 'd', parentId: 'r', name: '体育', goal: 2, earned: 2),
        ]),
      );
      expect(plan.shortLeaves.map((g) => g.name), ['数学']);
    });

    test('cache round trip', () {
      final audit = DegreeAudit(
        plans: [
          DegreePlan.fromRows(
            plan: rowsOf('grpyfacx').single,
            audit: rowsOf('cxscfa').single,
            groups: rowsOf('cxscfakz'),
            groupSelected: const {'0046e45abf1a45008f0767bf18bc51a8': 4},
          ),
        ],
        syncedAt: DateTime.utc(2026, 10, 13),
      );
      final back = DegreeAudit.decode(audit.encode())!;
      expect(back.syncedAt, audit.syncedAt);
      final plan = back.plans.single;
      expect(plan.earned, 51);
      expect(
        plan.allGroups
            .firstWhere((g) => g.id == '0046e45abf1a45008f0767bf18bc51a8')
            .selected,
        4,
      );
      expect(DegreeAudit.decode('{bad'), isNull);
    });
  });

  test('EhallService.degreeAudit posts the official read-only forms', () async {
    final protocol = EduProtocol();
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    )..httpClientAdapter = protocol;
    final ehall = EhallService(CasClient(cookieJar: CookieJar(), dio: dio));
    const base = '/jwapp/sys/xywccx';
    protocol
      ..reply('GET', '$base/*default/index.do', '<html></html>')
      ..reply(
        'GET',
        '/jwapp/sys/funauthapp/api/getAppConfig/xywccx-4980269146247992.do',
        {'APP_ID': '4980269146247992', 'MODULES': []},
      );
    final forms = <String, Map<String, String>>{};
    void post(String endpoint, Object Function(Map<String, String>) body) {
      protocol.add('POST', '$base/modules/xywccx/$endpoint', (r) {
        final form = {
          for (final e in (r.data as Map).entries) '${e.key}': '${e.value}',
        };
        forms[endpoint] = form;
        return EduProtocol.response(body(form));
      });
    }

    post('grpyfacx.do', (_) => live['grpyfacx'] as Object);
    post('cxdqxnxq.do', (_) => live['cxdqxnxq'] as Object);
    post('cxscfa.do', (_) => live['cxscfa'] as Object);
    post('cxscfakz.do', (_) => live['cxscfakz'] as Object);
    final selected = live['cxfakzyxxfgj'] as Map<String, dynamic>;
    // Plan total, then one request per group.
    for (var i = 0; i < 5; i++) {
      post(
        'cxfakzyxxfgj.do',
        (form) => selected[form['KZH'] ?? ''] ?? selected['']!,
      );
    }

    final audit = await ehall.degreeAudit('2024012001', parallel: 1);
    expect(protocol.steps, isEmpty);
    expect(forms['grpyfacx.do'], {'XH': '2024012001'});
    expect(forms['cxscfa.do'], {
      'XH': '2024012001',
      'PYFADM': '8cef7a8dec1f4e6dbb51bac6face811c',
      'BYNJDM': '-',
      'SCLBDM': '04',
    });
    expect(forms['cxscfakz.do']!['XNXQDM'], '2026-2027-1');
    expect(forms['cxfakzyxxfgj.do']!.keys, containsAll(['KZLXDM', 'KZH']));
    // Nothing that recalculates: every POST went to a query endpoint.
    expect(
      protocol.requests.where((r) => r.method == 'POST').map((r) => r.uri.path),
      everyElement(
        anyOf(
          endsWith('grpyfacx.do'),
          endsWith('cxdqxnxq.do'),
          endsWith('cxscfa.do'),
          endsWith('cxscfakz.do'),
          endsWith('cxfakzyxxfgj.do'),
        ),
      ),
    );
    final plan = audit.plans.single;
    expect(plan.selected, 28);
    final group = plan.allGroups.firstWhere(
      (g) => g.id == '0046e45abf1a45008f0767bf18bc51a8',
    );
    expect(group.selected, 4);
  });
}
