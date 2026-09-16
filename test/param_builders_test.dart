// Locks the add/delete/query param JSON to the exact shapes the site sends
// (mirrors scripts/request-builders.mjs output — key order and separators).
// Also verifies the correctness-critical resolveAddParam rules: a class that
// hasTest/hasBook must carry testTeachingClassID/needBook, and refuses to build
// an incomplete grab.
import 'dart:convert';

import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/data/param_builders.dart';
import 'package:test/test.dart';

TeachingClass tc({
  String id = 'TC1',
  bool hasTest = false,
  String testId = '',
  bool hasBook = false,
}) =>
    TeachingClass.fromJson({
      'teachingClassID': id,
      'courseNumber': 'C1',
      'courseName': '课程',
      'hasTest': hasTest ? '1' : '0',
      'testTeachingClassID': testId,
      'hasBook': hasBook ? '1' : '0',
    });

void main() {
  group('buildCourseQuery', () {
    test('FANKC includes check flags in frontend key order', () {
      final f = buildCourseQuery(
        studentCode: 'S', campus: 'CA', electiveBatchCode: 'B',
        kind: CourseKind.fankc,
      );
      expect(
        f['querySetting'],
        '{"data":{"studentCode":"S","campus":"CA","electiveBatchCode":"B",'
        '"isMajor":"1","teachingClassType":"FANKC","checkConflict":"2",'
        '"checkCapacity":"2","queryContent":""},"pageSize":"10","pageNumber":"0","order":""}',
      );
    });

    test('QXKC omits check flags', () {
      final f = buildCourseQuery(
        studentCode: 'S', campus: 'CA', electiveBatchCode: 'B',
        kind: CourseKind.qxkc,
      );
      final decoded = jsonDecode(f['querySetting']!) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>;
      expect(data.containsKey('checkConflict'), isFalse);
      expect(data.containsKey('checkCapacity'), isFalse);
      expect(data['teachingClassType'], 'QXKC');
    });

    test('FXKC sends isMajor=0', () {
      final f = buildCourseQuery(
        studentCode: 'S', campus: 'CA', electiveBatchCode: 'B',
        kind: CourseKind.fxkc,
      );
      final data = (jsonDecode(f['querySetting']!) as Map)['data'] as Map;
      expect(data['isMajor'], '0');
    });
  });

  group('resolveAddParam selection accuracy', () {
    const ctx = (studentCode: 'S', batch: 'B', campus: 'CA');

    test('plain class builds shortest addParam', () {
      final plan = resolveAddParam(
        tc: tc(), studentCode: ctx.studentCode, electiveBatchCode: ctx.batch,
        campus: ctx.campus, kind: CourseKind.fankc,
      );
      expect(plan.shape, AddShape.plain);
      expect(
        plan.form['addParam'],
        '{"data":{"operationType":"1","studentCode":"S","electiveBatchCode":"B",'
        '"teachingClassId":"TC1","isMajor":"1","campus":"CA","teachingClassType":"FANKC"}}',
      );
    });

    test('hasTest requires testTeachingClassID — refuses without it', () {
      expect(
        () => resolveAddParam(
          tc: tc(hasTest: true),
          studentCode: ctx.studentCode, electiveBatchCode: ctx.batch,
          campus: ctx.campus, kind: CourseKind.fankc,
        ),
        throwsA(isA<MissingSelectionError>()),
      );
    });

    test('hasTest with resolved test class emits testTeachingClassID', () {
      final plan = resolveAddParam(
        tc: tc(hasTest: true),
        studentCode: ctx.studentCode, electiveBatchCode: ctx.batch,
        campus: ctx.campus, kind: CourseKind.fankc,
        selectedTestTeachingClassId: 'TEST9',
      );
      expect(plan.shape, AddShape.withTest);
      final data = (jsonDecode(plan.form['addParam']!) as Map)['data'] as Map;
      expect(data['testTeachingClassID'], 'TEST9');
    });

    test('hasBook requires needBook — refuses without it', () {
      expect(
        () => resolveAddParam(
          tc: tc(hasBook: true),
          studentCode: ctx.studentCode, electiveBatchCode: ctx.batch,
          campus: ctx.campus, kind: CourseKind.fankc,
        ),
        throwsA(isA<MissingSelectionError>()),
      );
    });

    test('textbook ordering closed skips needBook even when hasBook', () {
      final plan = resolveAddParam(
        tc: tc(hasBook: true),
        studentCode: ctx.studentCode, electiveBatchCode: ctx.batch,
        campus: ctx.campus, kind: CourseKind.fankc,
        textbookOrderingOpen: false,
      );
      expect(plan.shape, AddShape.plain);
    });

    test('test + book emits both, needBook before testTeachingClassID', () {
      final plan = resolveAddParam(
        tc: tc(hasTest: true, hasBook: true),
        studentCode: ctx.studentCode, electiveBatchCode: ctx.batch,
        campus: ctx.campus, kind: CourseKind.fankc,
        selectedTestTeachingClassId: 'TEST9',
        bookSelection: 'BK1,BK2-03',
      );
      expect(plan.shape, AddShape.withTestAndBook);
      expect(
        plan.form['addParam'],
        contains('"needBook":"BK1,BK2-03","testTeachingClassID":"TEST9"'),
      );
    });
  });

  group('预选 (volunteer) rounds', () {
    const ctx = (studentCode: 'S', batch: 'B', campus: 'CA');
    test('chooseVolunteer comes right after teachingClassType, then test, then book', () {
      final plan = resolveAddParam(
        tc: tc(hasTest: true, hasBook: true),
        studentCode: ctx.studentCode, electiveBatchCode: ctx.batch,
        campus: ctx.campus, kind: CourseKind.xgxk,
        selectedTestTeachingClassId: 'TEST9',
        bookSelection: 'BK1',
        volunteerGrade: '2',
      );
      expect(
        plan.form['addParam'],
        '{"data":{"operationType":"1","studentCode":"S","electiveBatchCode":"B",'
        '"teachingClassId":"TC1","isMajor":"1","campus":"CA","teachingClassType":"XGXK",'
        '"chooseVolunteer":"2","testTeachingClassID":"TEST9","needBook":"BK1"}}',
      );
      expect(plan.shapeLabel, contains('第2志愿'));
    });

    test('no grade means the 正选 shape without chooseVolunteer', () {
      final plan = resolveAddParam(
        tc: tc(),
        studentCode: ctx.studentCode, electiveBatchCode: ctx.batch,
        campus: ctx.campus, kind: CourseKind.fankc,
      );
      expect(plan.form['addParam'], isNot(contains('chooseVolunteer')));
      expect(plan.chooseVolunteer, isNull);
    });

    test('course/volunteer.do query carries the category and the class id as wid', () {
      final q = buildCourseVolunteerParam(
        studentCode: 'S', electiveBatchCode: 'B', courseNumber: 'K1',
        teachingClassType: 'XGXK', teachingClassId: 'TC1',
      );
      expect(
        q['queryParam'],
        '{"data":{"studentCode":"S","electiveBatchCode":"B","courseNumber":"K1",'
        '"teachingClassType":"XGXK","wid":"TC1"}}',
      );
    });
  });

  group('buildDeleteVolunteerParam', () {
    test('matches frontend shape', () {
      final f = buildDeleteVolunteerParam(
        studentCode: 'S', electiveBatchCode: 'B', teachingClassId: 'TC1',
      );
      expect(
        f['deleteParam'],
        '{"data":{"operationType":"2","studentCode":"S","electiveBatchCode":"B",'
        '"teachingClassId":"TC1","isMajor":"1"}}',
      );
    });
  });

  group('buildBookSelection', () {
    test('ordered vs declined books', () {
      final s = buildBookSelection([
        BookChoice(bookCode: 'A', order: true),
        BookChoice(bookCode: 'B', order: false, reasonCode: '03'),
      ]);
      expect(s, 'A,B-03');
    });
    test('rejects a declined book without a reason', () {
      expect(
        () => buildBookSelection([
          BookChoice(bookCode: 'B', order: false),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects the official placeholder reason', () {
      expect(
        () => buildBookSelection([
          BookChoice(bookCode: 'B', order: false, reasonCode: '***'),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('buildScheduleQuery', () {
    test('threads student + batch + timestamp', () {
      final q = buildScheduleQuery(
        studentCode: 'S', electiveBatchCode: 'B', timestamp: 'T1',
      );
      expect(q, {'studentCode': 'S', 'electiveBatchCode': 'B', 'timestamp': 'T1'});
    });
  });

  group('buildUnsuccessfulQuery', () {
    test('always sends isRead (the server rejects its absence), 0 by default', () {
      final q = buildUnsuccessfulQuery(studentCode: 'S', electiveBatchCode: 'B');
      expect(q['isRead'], '0');
      expect(q['studentCode'], 'S');
      expect(q['electiveBatchCode'], 'B');
    });
    test('includes isRead=1 when requested', () {
      final q = buildUnsuccessfulQuery(
        studentCode: 'S', electiveBatchCode: 'B', isRead: true,
      );
      expect(q['isRead'], '1');
    });
  });

  group('buildTeachingClassDetailQuery', () {
    test('uses jxbid + xklcdm', () {
      final q = buildTeachingClassDetailQuery(
        teachingClassId: 'TC1', electiveBatchCode: 'B',
      );
      expect(q, {'jxbid': 'TC1', 'xklcdm': 'B'});
    });
  });

  group('buildCourseDetailQuery', () {
    test('uses kch key', () {
      expect(buildCourseDetailQuery('C101'), {'kch': 'C101'});
    });
  });

  group('buildCourseVolunteerParam', () {
    test('wraps data inside queryParam', () {
      final f = buildCourseVolunteerParam(
        studentCode: 'S', electiveBatchCode: 'B', courseNumber: 'C1',
      );
      final decoded = jsonDecode(f['queryParam']!) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>;
      expect(data['studentCode'], 'S');
      expect(data['courseNumber'], 'C1');
    });
  });

  group('buildCreditInfoParam', () {
    test('includes xklclx when provided', () {
      final p = buildCreditInfoParam(
        studentCode: 'S', electiveBatchCode: 'B', xklclx: '02',
      );
      expect(p, {'xh': 'S', 'xklcdm': 'B', 'xklclx': '02'});
    });
    test('omits xklclx when empty', () {
      final p = buildCreditInfoParam(
        studentCode: 'S', electiveBatchCode: 'B',
      );
      expect(p.containsKey('xklclx'), isFalse);
    });
  });

  group('buildLogoutQuery', () {
    test('uses studentNumber + timestamp', () {
      final q = buildLogoutQuery(studentCode: 'S', timestamp: 'T1');
      expect(q, {'studentNumber': 'S', 'timestamp': 'T1'});
    });
  });

  group('buildTextbookModifyParam', () {
    test('czlx=1 by default (modify)', () {
      final p = buildTextbookModifyParam(
        studentCode: 'S', electiveBatchCode: 'B',
        teachingClassId: 'TC1', jcxx: 'BK1',
      );
      expect(p['czlx'], '1');
      expect(p['jcxx'], 'BK1');
    });
    test('czlx=0 when cancelAll', () {
      final p = buildTextbookModifyParam(
        studentCode: 'S', electiveBatchCode: 'B',
        teachingClassId: 'TC1', jcxx: 'BK1-03', cancelAll: true,
      );
      expect(p['czlx'], '0');
    });
  });

  group('testTeachingClassIdFromRow', () {
    test('skips an empty canonical field and uses a valid alias', () {
      expect(
        testTeachingClassIdFromRow({
          'testTeachingClassID': '',
          'teachingClassID': ' TC-LAB-01 ',
        }),
        'TC-LAB-01',
      );
    });

    test('returns null when every known field is blank or absent', () {
      expect(testTeachingClassIdFromRow({'teachingClassId': '  '}), isNull);
    });
  });


  group('buildBatchConfirmParam', () {
    test('matches xklcqr.do form fields', () {
      expect(
        buildBatchConfirmParam(studentCode: 'S', electiveBatchCode: 'B'),
        {'studentCode': 'S', 'electiveBatchCode': 'B'},
      );
    });
  });
  group('buildNoticeListQuery', () {
    test('threads pageSize + pageNumber + timestamp', () {
      final q = buildNoticeListQuery(timestamp: 'T1', pageSize: 20, pageNumber: 2);
      expect(q, {'pageSize': '20', 'pageNumber': '2', 'timestamp': 'T1'});
    });
  });
}
