import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/ehall_service.dart';

void main() {
  test("week 1 is anchored to the school's current week (dqzc.do)", () {
    // 2026-10-11 (Sun) is week 5 → week 1 began Mon 2026-09-07.
    expect(
      weekOneMondayFrom({'ZC': 5, 'XQJ': 7}, DateTime.utc(2026, 10, 11)),
      DateTime.utc(2026, 9, 7),
    );
    // A Wednesday in week 1 maps back to that week's Monday.
    expect(
      weekOneMondayFrom({'ZC': '1'}, DateTime.utc(2026, 9, 16)),
      DateTime.utc(2026, 9, 14),
    );
    expect(weekOneMondayFrom(null, DateTime.utc(2026, 9, 16)), isNull);
    expect(weekOneMondayFrom({'ZC': 0}, DateTime.utc(2026, 9, 16)), isNull);
  });
}
