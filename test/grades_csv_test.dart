import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/edu_models.dart';

void main() {
  test('grades CSV has a BOM, CRLF rows and quotes commas', () {
    final r = GradeRecord.fromRow({
      'XNXQDM': '2025-2026-2',
      'XNXQDM_DISPLAY': '2025-2026学年 春',
      'KCM': '书法鉴赏, 入门',
      'KCH': 'X1',
      'XF': 2,
      'ZCJ': 92,
      'XFJD': 4.2,
    });
    final csv = gradesCsv([r]);
    expect(csv.startsWith('﻿学期,'), isTrue);
    final lines = csv.split('\r\n');
    expect(
      lines[1],
      startsWith('2025-2026学年 春,"书法鉴赏, 入门",X1,2,92,4.2'),
    );
  });
}
