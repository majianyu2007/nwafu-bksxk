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
  String toString() =>
      'EnrollOutcome(success=$success, code=$code, msg=$message)';
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
    String? volunteerGrade,
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
      volunteerGrade: volunteerGrade,
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
    if (!res.ok) {
      return EnrollOutcome(
        success: false,
        code: res.code,
        message: res.msg.isEmpty ? '退选失败' : res.msg,
      );
    }
    // Like adds, drops are queued server-side; the official page waits for
    // studentstatus.do before reporting the outcome.
    final status = await confirmStatus(studentCode);
    final rejected = status.code == '-1';
    return EnrollOutcome(
      success: !rejected,
      code: rejected ? status.code : res.code,
      message: rejected
          ? (status.msg.isEmpty ? '退选未成功' : status.msg)
          : (res.msg.isEmpty ? '退选成功' : res.msg),
    );
  }

  /// Polls the post-operation processing status. The server processes add/drop
  /// asynchronously; this confirms the final result.
  Future<ApiResult> pollStatus(String studentCode) {
    return _client.postForm(
        Api.studentStatus, buildStudentStatusParam(studentCode));
  }

  /// Polls status until it settles or [attempts] is exhausted. Returns the
  /// last result. Used after a successful submit to confirm the seat stuck.
  ///
  /// The official page polls studentstatus.do once a second, up to ten times,
  /// and treats code "1" as processed and "-1" as rejected (msg says why);
  /// anything else means the queue is still working.
  Future<ApiResult> confirmStatus(
    String studentCode, {
    int attempts = 10,
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    ApiResult last = await pollStatus(studentCode);
    for (var i = 1; i < attempts; i++) {
      if (last.code == '1' || last.code == '-1') return last;
      await Future<void>.delayed(interval);
      last = await pollStatus(studentCode);
    }
    return last;
  }

  // ---- Textbook write ops ----

  /// Orders the textbooks for a class (addbook.do). Called when the student
  /// confirms an order for every book the class offers (the default grab
  /// flow) — no per-book declination here; use [modifyTextbook] for that.
  Future<EnrollOutcome> orderTextbook({
    required String studentCode,
    required String batchCode,
    required String teachingClassId,
  }) async {
    final res = await _client.postForm(
      Api.textbookAdd,
      buildTextbookOrderParam(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
        teachingClassId: teachingClassId,
      ),
    );
    return EnrollOutcome(
      success: res.ok,
      code: res.code,
      message: res.msg.isEmpty ? (res.ok ? '教材订购成功' : '教材订购失败') : res.msg,
    );
  }

  /// Modifies / cancels a textbook order (modifybook.do). [jcxx] is the
  /// per-book selection string (see [buildBookSelection]); [cancelAll] sends
  /// `czlx=0` to fully unsubscribe rather than `czlx=1` to modify.
  Future<EnrollOutcome> modifyTextbook({
    required String studentCode,
    required String batchCode,
    required String teachingClassId,
    required String jcxx,
    bool cancelAll = false,
  }) async {
    final res = await _client.postForm(
      Api.textbookModify,
      buildTextbookModifyParam(
        studentCode: studentCode,
        electiveBatchCode: batchCode,
        teachingClassId: teachingClassId,
        jcxx: jcxx,
        cancelAll: cancelAll,
      ),
    );
    return EnrollOutcome(
      success: res.ok,
      code: res.code,
      message: res.msg.isEmpty
          ? (res.ok ? (cancelAll ? '教材已退订' : '教材已修改') : '教材操作失败')
          : res.msg,
    );
  }
}
