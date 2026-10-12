import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nwafu_bksxk/app/edu_providers.dart';
import 'package:nwafu_bksxk/app/providers.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:nwafu_bksxk/ui/timetable/course_sheets.dart';
import 'package:nwafu_bksxk/ui/timetable_page.dart';

const _term = EduTerm(code: '2026-2027-1', name: '2026-2027学年 秋');

TermTimetable _table() => TermTimetable(
  term: _term,
  firstMonday: DateTime.utc(2026, 9, 7),
  weekCount: 4,
  periods: const [
    ClassPeriod(index: 1, start: 480, end: 525),
    ClassPeriod(index: 2, start: 535, end: 580),
    ClassPeriod(index: 3, start: 610, end: 655),
    ClassPeriod(index: 4, start: 665, end: 710),
  ],
  sessions: const [
    CourseSession(
      id: 'A',
      courseName: '高等数学',
      courseCode: 'MATH1',
      classNo: '1',
      weekday: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: [1, 2, 3, 4],
      weeksLabel: '1-4周',
      room: 'N8603',
      teacher: '张老师',
    ),
    CourseSession(
      id: 'B',
      courseName: '马克思主义基本原理概论',
      courseCode: 'MKS',
      classNo: '1',
      weekday: 2,
      startPeriod: 3,
      endPeriod: 4,
      weeks: [1, 3],
      weeksLabel: '1-3周(单)',
      room: 'N9402',
    ),
  ],
  syncedAt: DateTime.utc(2026, 9, 7),
);

Future<Storage> _storage() async {
  SharedPreferences.setMockInitialValues({});
  final storage = Storage(await SharedPreferences.getInstance());
  await storage.setEduAccount(const EduAccount(username: 'fixture').encode());
  await storage.setEduCurrentTerm('fixture', jsonEncode(_term.toJson()));
  await storage.setEduTimetable('fixture', _term.code, _table().encode());
  return storage;
}

Widget _app(Storage storage, DateTime now, Widget child) => ProviderScope(
  overrides: [
    storageProvider.overrideWithValue(storage),
    clockProvider.overrideWith((ref) => Stream.value(now)),
    examsProvider.overrideWith((ref) async => <ExamEntry>[]),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('day view on a phone lists the classes of the chosen date', (
    tester,
  ) async {
    final storage = await _storage();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Monday 2026-09-07 08:20 CST: 高等数学 is in progress.
    await tester.pumpWidget(
      _app(storage, DateTime.utc(2026, 9, 7, 0, 20), const TimetablePage()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PageView), findsNothing, reason: 'phones open the day view');
    expect(find.text('高等数学'), findsWidgets);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.textContaining('9月7日 · 周一 · 1 节课'), findsOneWidget);
    expect(find.text('马克思主义基本原理概论'), findsNothing);

    // Tuesday: the long course name is shown in full, Monday's class is not
    // in the timeline any more.
    await tester.tap(find.bySemanticsLabel(RegExp('^周二 9月8日')));
    await tester.pumpAndSettle();
    expect(find.textContaining('9月8日 · 周二 · 1 节课'), findsOneWidget);
    expect(find.text('马克思主义基本原理概论'), findsOneWidget);
    expect(find.text('即将开始'), findsNothing);

    // Week 2 Tuesday: the odd-week class does not run.
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(find.textContaining('9月15日 · 周二 · 无课'), findsOneWidget);
    expect(find.text('这一天没有课程'), findsOneWidget);

    // The toggle switches to the week grid and is remembered.
    await tester.tap(find.byTooltip('切换为周视图'));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('custom course validation reports every bad field', () {
    final bad = validateCustomCourse(
      id: 'c1',
      name: '  ',
      room: '',
      teacher: '',
      weekday: 3,
      startPeriod: 4,
      endPeriod: 2,
      weeksText: '1-99周',
      maxWeek: 18,
      maxPeriod: 12,
    );
    expect(bad.ok, isFalse);
    expect(bad.errors.keys, containsAll(['name', 'period', 'weeks']));

    final good = validateCustomCourse(
      id: 'c1',
      name: ' 社团活动 ',
      room: '南校区',
      teacher: '',
      weekday: 3,
      startPeriod: 3,
      endPeriod: 4,
      weeksText: '1-15周(单)',
      maxWeek: 18,
      maxPeriod: 12,
    );
    expect(good.ok, isTrue);
    final s = good.session!;
    expect(s.courseName, '社团活动');
    expect(s.custom, isTrue);
    expect(s.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    expect(s.weeksLabel, '1-15周(单)');

    final clash = conflictsWith(
      _table(),
      validateCustomCourse(
        id: 'c2',
        name: 'x',
        room: '',
        teacher: '',
        weekday: 2,
        startPeriod: 4,
        endPeriod: 4,
        weeksText: '3周',
      ).session!,
    );
    expect(clash.map((c) => c.id), ['B']);
  });

  testWidgets('custom course editor refuses to save without a name', (
    tester,
  ) async {
    final storage = await _storage();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        storage,
        DateTime.utc(2026, 9, 7, 0, 20),
        CustomCourseEditor(data: _table(), weekday: 2),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入课程名称'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '周次'), '2-4周');
    await tester.enterText(find.widgetWithText(TextField, '课程名称'), '自习');
    await tester.pumpAndSettle();
    expect(find.textContaining('共 3 周'), findsOneWidget);
    // Tuesday 1–2 overlaps nothing; switch to periods 3–4 to clash with B in
    // week 3.
    await tester.enterText(find.widgetWithText(TextField, '周次'), '3周');
    await tester.pumpAndSettle();
    expect(find.textContaining('时间重叠'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, '周次'), '第九十周');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法识别的周次'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
