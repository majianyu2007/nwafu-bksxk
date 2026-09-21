import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/academic_calendar.dart';
import 'package:nwafu_bksxk/data/update_service.dart';

void main() {
  test('reported term advances at Monday and never seeds other terms', () {
    final calendar = AcademicCalendar.reportedFor(
        const AcademicTerm(id: '2026-2027-1', label: '秋'))!;
    expect(calendar.weekOn(DateTime.utc(2026, 9, 21)), 3);
    expect(calendar.weekOn(DateTime.utc(2026, 9, 27)), 3);
    expect(calendar.weekOn(DateTime.utc(2026, 9, 28)), 4);
    expect(
        AcademicCalendar.reportedFor(
            const AcademicTerm(id: '2027-2028-1', label: '秋')),
        isNull);
  });
  test('stable update ordering is numeric and ignores build metadata', () {
    expect(isNewerStableVersion('v1.10.0', '1.9.0'), isTrue);
    expect(isNewerStableVersion('1.2.0+9', '1.2.0+3'), isFalse);
    expect(isNewerStableVersion('2.0.0-beta.1', '1.2.0'), isFalse);
    expect(isNewerStableVersion('garbage', '1.2.0'), isFalse);
    expect(isNewerStableVersion('1.1.0', '1.2.0'), isFalse);
  });
}
