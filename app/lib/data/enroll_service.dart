/// Enrollment: add (grab), drop, and post-operation status polling.
///
/// The add path is deliberately split into "resolve" (build the exact param,
/// possibly needing a test class / textbook string) and "submit" (fire
/// volunteer.do). The monitor pre-resolves the param the instant it starts
/// watching, so when a seat opens the submit is a single round-trip with zero
/// decision-making in the hot path — that's the "抢课快人一步" guarantee.
library;

import '../core/constants.dart';
import 'api_client.dart';
import 'models.dart';
import 'param_builders.dart';

/// Outcome of an add/drop submission.
class EnrollOutcome {
  EnrollOutcome({
    required this.success,
    required this.code,
    required this.message,
    this.shape,
  });

  final bool success;
  final String code;
  final String message;

  /// Which submission shape was used (for add).
  final AddShape? shape;

  @override
  String toString() => 'EnrollOutcome(success=$success, code=$code, msg=$message)';
}

class EnrollService {
  EnrollService(this._client);

  final ApiClient _client;

  /// Submits a pre-built add param. This is the hot-path call — no logic, just
  /// the POST — so a grab is as fast as the network allows.
  Future<EnrollOutcome> submitAdd(AddParamPlan plan) async {
    final res = await _client.postForm(Api.volunteer, plan.form);
    return EnrollOutcome(
      success: res.ok,
      code: res.code,
      message: res.msg.isEmpty ? (res.ok ? '提交成功' : '提交失败') : res.msg,
      shape: plan.shape,
    );
  }

  /// Convenience: resolve + submit in one call (used for manual, non-monitored
  /// selection where the user already picked test class / textbook).
  Future<EnrollOutcome> addCourse({
    required TeachingClass tc,
    required String studentCode,
    required String batchCode,
    required String campus,
    required CourseKind kind,
    String? selectedTestTeachingClassId,
    String? bookSelection,
    bool textbookOrderingOpen = true,
  }) async {
    final plan = resolveAddParam(
      tc: tc,
      studentCode: studentCode,
      electiveBatchCode: batchCode,
      campus: campus,
      kind: kind,
      selectedTestTeachingClassId: selectedTestTeachingClassId,
      bookSelection: bookSelection,
      textbookOrderingOpen: textbookOrderingOpen,
    );
    return submitAdd(plan);
  }

  /// Drops a selected class.
  Future<EnrollOutcome> dropCourse({
    required String teachingClassId,
    required String studentCode,
    required String batchCode,
    String isMajor = '1',
  }) async {
    final form = buildDeleteVolunteerParam(
      studentCode: studentCode,
      electiveBatchCode: batchCode,
      teachingClassId: teachingClassId,
      isMajor: isMajor,
    );
    final res = await _client.getJson(
      Api.deleteVolunteer,
      query: form,
      addTimestamp: true,
    );
    return EnrollOutcome(
      success: res.ok,
      code: res.code,
      message: res.msg.isEmpty ? (res.ok ? '退选成功' : '退选失败') : res.msg,
    );
  }

  /// Polls the post-operation processing status. The server processes add/drop
  /// asynchronously; this confirms the final result.
  Future<ApiResult> pollStatus(String studentCode) {
    return _client.postForm(Api.studentStatus, buildStudentStatusParam(studentCode));
  }

  /// Polls status until it resolves or [attempts] is exhausted. Returns the last
  /// result. Used after a successful submit to confirm the seat stuck.
  Future<ApiResult> confirmStatus(
    String studentCode, {
    int attempts = 6,
    Duration interval = const Duration(milliseconds: 400),
  }) async {
    ApiResult last = await pollStatus(studentCode);
    for (var i = 1; i < attempts; i++) {
      // code=1 with a settled message usually means processed.
      if (last.ok && last.msg.isNotEmpty) return last;
      await Future<void>.delayed(interval);
      last = await pollStatus(studentCode);
    }
    return last;
  }
}
