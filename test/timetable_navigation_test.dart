import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nwafu_bksxk/app/edu_providers.dart';
import 'package:nwafu_bksxk/app/providers.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:nwafu_bksxk/ui/timetable_page.dart';

void main() {
  testWidgets('week arrows and swipe keep the grid and selected dates aligned', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = Storage(await SharedPreferences.getInstance());
    const term = EduTerm(code: '2026-2027-1', name: '2026-2027学年 秋');
    final table = TermTimetable(term: term, firstMonday: DateTime.utc(2026, 9, 7), weekCount: 3,
      periods: const [ClassPeriod(index: 1, start: 480, end: 525)],
      sessions: const [CourseSession(id: 'A', courseName: '测试课程', courseCode: 'A', classNo: '1',
        weekday: 1, startPeriod: 1, endPeriod: 1, weeks: [1, 2, 3], weeksLabel: '1-3周')], syncedAt: DateTime.utc(2026, 9, 7));
    await storage.setEduAccount(const EduAccount(username: 'fixture').encode());
    await storage.setEduCurrentTerm('fixture', jsonEncode(term.toJson()));
    await storage.setEduTimetable('fixture', term.code, table.encode());
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      storageProvider.overrideWithValue(storage),
      clockProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 9, 7))),
      examsProvider.overrideWith((ref) async => <ExamEntry>[]),
    ], child: const MaterialApp(home: Scaffold(body: TimetablePage()))));
    await tester.pumpAndSettle();
    expect(find.textContaining('9月7日 — 9月13日'), findsOneWidget);
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('9月14日 — 9月20日'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('9月21日 — 9月27日'), findsOneWidget);
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('9月7日 — 9月13日'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
