/// Pure-Dart GPA / weighted-average simulator ("如果这门课考 X 分，均绩会变多少").
library;

import 'edu_models.dart';

/// A hypothetical course added inside the GPA simulator.
class SimulatedCourse {
  const SimulatedCourse({
    required this.name,
    required this.credit,
    required this.gradePoint,
    this.score,
  });

  final String name;
  final double credit;
  final double gradePoint;
  final double? score;
}

class GpaSimulationResult {
  const GpaSimulationResult({
    required this.baseGpa,
    required this.simulatedGpa,
    required this.baseCredits,
    required this.simulatedCredits,
    this.baseAverage,
    this.simulatedAverage,
  });

  final double baseGpa;
  final double simulatedGpa;
  final double baseCredits;
  final double simulatedCredits;
  final double? baseAverage;
  final double? simulatedAverage;

  double get gpaDelta => simulatedGpa - baseGpa;
}

/// Converts a 0–100 score to a 4.0-scale grade point (NWAFU linear/capped rule:
/// < 60 → 0.0, 60–90 → (score - 50) / 10, >= 90 → 4.0).
double scoreToGpa(double score) {
  if (!score.isFinite || score < 60) return 0.0;
  if (score >= 90) return 4.0;
  return double.parse(((score - 50) / 10).toStringAsFixed(2));
}

/// Inverse of [scoreToGpa]: minimum 0–100 score needed to achieve [gp]
/// (clamped to `[60, 90]` for `gp` in `(0, 4]`, or `0` for `<= 0`).
double gpaToEstimatedScore(double gp) {
  if (!gp.isFinite || gp <= 0) return 0;
  if (gp >= 4.0) return 90;
  return (gp * 10 + 50).clamp(60, 90).toDouble();
}

/// Result of reverse-calculating the required average GPA over upcoming credits
/// to hit a desired cumulative GPA target (e.g. 3.60 for 保研 / 3.40 奖学金).
class TargetGpaPlan {
  const TargetGpaPlan({
    required this.targetGpa,
    required this.currentGpa,
    required this.currentCredits,
    required this.upcomingCredits,
    required this.requiredGpa,
  });

  final double targetGpa;
  final double currentGpa;
  final double currentCredits;
  final double upcomingCredits;
  final double requiredGpa;

  bool get alreadyReached => requiredGpa <= 0;
  bool get achievable => requiredGpa <= 4.0;
  double get estimatedScore => gpaToEstimatedScore(requiredGpa);
}

/// Computes the average GPA required across [upcomingCredits] to move from
/// ([currentGpa], [currentCredits]) to [targetGpa].
TargetGpaPlan? planTargetGpa({
  required double currentGpa,
  required double currentCredits,
  required double upcomingCredits,
  required double targetGpa,
}) {
  if (!currentGpa.isFinite ||
      !currentCredits.isFinite ||
      !upcomingCredits.isFinite ||
      !targetGpa.isFinite ||
      upcomingCredits <= 0 ||
      targetGpa <= 0 ||
      targetGpa > 4.0) {
    return null;
  }
  final neededPoints =
      targetGpa * (currentCredits + upcomingCredits) -
      currentGpa * currentCredits;
  final required = neededPoints / upcomingCredits;
  return TargetGpaPlan(
    targetGpa: targetGpa,
    currentGpa: currentGpa,
    currentCredits: currentCredits,
    upcomingCredits: upcomingCredits,
    requiredGpa: required,
  );
}

/// Computes baseline vs simulated GPA from existing [records], optional
/// [excludedIndices], and added [hypothetical] courses.
GpaSimulationResult simulateGpa({
  required List<GradeRecord> records,
  Set<int> excludedIndices = const {},
  List<SimulatedCourse> hypothetical = const [],
}) {
  double baseGpSum = 0;
  double baseGpCred = 0;
  double baseScoreSum = 0;
  double baseScoreCred = 0;

  double simGpSum = 0;
  double simGpCred = 0;
  double simScoreSum = 0;
  double simScoreCred = 0;

  for (var i = 0; i < records.length; i++) {
    final r = records[i];
    if (r.credit <= 0) continue;
    final gp = r.gradePoint;
    if (gp != null) {
      baseGpSum += gp * r.credit;
      baseGpCred += r.credit;
      if (!excludedIndices.contains(i)) {
        simGpSum += gp * r.credit;
        simGpCred += r.credit;
      }
    }
    final sc = r.score;
    if (sc != null) {
      baseScoreSum += sc * r.credit;
      baseScoreCred += r.credit;
      if (!excludedIndices.contains(i)) {
        simScoreSum += sc * r.credit;
        simScoreCred += r.credit;
      }
    }
  }

  for (final c in hypothetical) {
    if (!c.credit.isFinite || c.credit <= 0 || !c.gradePoint.isFinite) continue;
    simGpSum += c.gradePoint * c.credit;
    simGpCred += c.credit;
    if (c.score != null && c.score!.isFinite) {
      simScoreSum += c.score! * c.credit;
      simScoreCred += c.credit;
    }
  }

  return GpaSimulationResult(
    baseGpa: baseGpCred > 0 ? baseGpSum / baseGpCred : 0,
    simulatedGpa: simGpCred > 0 ? simGpSum / simGpCred : 0,
    baseCredits: baseGpCred,
    simulatedCredits: simGpCred,
    baseAverage: baseScoreCred > 0 ? baseScoreSum / baseScoreCred : null,
    simulatedAverage: simScoreCred > 0 ? simScoreSum / simScoreCred : null,
  );
}
