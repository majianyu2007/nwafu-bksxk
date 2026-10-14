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
  testWidgets('long names and large text never overflow a week cell', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'ui.timetable_view.v1': 'week'});
    final storage = Storage(await SharedPreferences.getInstance());
    const term = EduTerm(code: '2026-2027-1', name: '秋');
    final long = '马克思主义基本原理概论与中国特色社会主义理论体系研究专题' * 2;
    final table = TermTimetable(
      term: term,
      firstMonday: DateTime.utc(2026, 10, 12),
      weekCount: 1,
      periods: ClassPeriod.nwafuWinter,
      sessions: [
        for (var d = 1; d <= 7; d++)
          CourseSession(
            id: 'c$d',
            courseName: long,
            courseCode: 'K$d',
            classNo: '1',
            weekday: d,
            startPeriod: 1,
            endPeriod: 1,
            weeks: const [1],
            weeksLabel: '1周',
            room: '计算机机房202-B 北校区信息楼',
            teacher: '某某某老师',
          ),
      ],
      syncedAt: DateTime.utc(2026, 10, 1),
    );
    await storage.setEduAccount(const EduAccount(username: 'fixture').encode());
    await storage.setEduCurrentTerm('fixture', jsonEncode(term.toJson()));
    await storage.setEduTimetable('fixture', term.code, table.encode());
    for (final size in [const Size(360, 780), const Size(1200, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            clockProvider.overrideWith(
              (ref) => Stream.value(DateTime.utc(2026, 10, 12, 0, 20)),
            ),
            examsProvider.overrideWith((ref) async => <ExamEntry>[]),
          ],
          child: const MaterialApp(home: Scaffold(body: TimetablePage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  });
}
