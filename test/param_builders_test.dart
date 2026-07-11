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
  });
}
