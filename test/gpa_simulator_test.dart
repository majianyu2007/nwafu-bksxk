import 'package:flutter_test/flutter_test.dart';

import 'package:nwafu_bksxk/data/edu_models.dart';
import 'package:nwafu_bksxk/data/gpa_simulator.dart';

void main() {
  test('scoreToGpa follows NWAFU 4.0 conversion', () {
    expect(scoreToGpa(59), 0.0);
    expect(scoreToGpa(60), 1.0);
    expect(scoreToGpa(85), 3.5);
    expect(scoreToGpa(90), 4.0);
    expect(scoreToGpa(98), 4.0);
  });

  test('simulateGpa computes baseline, hypothetical additions, and exclusions',
      () {
    const records = [
      GradeRecord(
        termCode: '2025-2026-1',
        termName: '2025秋',
        courseName: '高等数学',
        courseCode: 'M1',
        credit: 4,
        scoreText: '80',
        score: 80,
        gradePoint: 3.0,
      ),
      GradeRecord(
        termCode: '2025-2026-1',
        termName: '2025秋',
        courseName: '大学英语',
        courseCode: 'E1',
        credit: 2,
        scoreText: '90',
        score: 90,
        gradePoint: 4.0,
      ),
    ];

    final added = simulateGpa(
      records: records,
      hypothetical: const [
        SimulatedCourse(name: '数据结构', credit: 4, gradePoint: 4.0, score: 95),
      ],
    );
    expect(added.baseGpa, closeTo(20 / 6, 1e-6));
    expect(added.simulatedGpa, closeTo(36 / 10, 1e-6));
    expect(added.gpaDelta, greaterThan(0));

    final excluded = simulateGpa(records: records, excludedIndices: const {0});
    expect(excluded.simulatedGpa, closeTo(4.0, 1e-6));
    expect(excluded.simulatedCredits, 2.0);
  });
}
