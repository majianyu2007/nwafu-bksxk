/// Request-parameter builders — a faithful Dart port of scripts/request-builders.mjs.
///
/// These construct the exact form fields the site sends. The most correctness-
/// sensitive part is [buildAddVolunteerParam]: whether testTeachingClassID and
/// needBook must be present is decided by the teaching-class flags, NOT left to
/// the caller's whim (see docs/api.notes.md "添加选课"). Getting this wrong is
/// the difference between grabbing a seat and silently failing.
///
/// Key wrapper: most course queries pack their real filter into a JSON *string*
/// field `querySetting`; add/delete pack into `addParam`/`deleteParam`. JSON key
/// order here matches the frontend so captured/generated examples line up.
library;

import 'dart:convert';

import '../core/constants.dart';
import 'models.dart';

/// Builds the `querySetting` form field for a course-list query.
Map<String, String> buildCourseQuery({
  required String studentCode,
  required String campus,
  required String electiveBatchCode,
  CourseKind kind = CourseKind.fankc,
  String checkConflict = '2',
  String checkCapacity = '2',
  String queryContent = '',
  int pageSize = 10,
  int pageNumber = 0,
  String order = '',
}) {
  final data = <String, dynamic>{
    'studentCode': studentCode,
    'campus': campus,
    'electiveBatchCode': electiveBatchCode,
    'isMajor': kind.isMajor,
    'teachingClassType': kind.code,
  };
  // Whole-school (QXKC) omits the two check flags, matching the frontend.
  if (kind.includesChecks) {
    data['checkConflict'] = checkConflict;
    data['checkCapacity'] = checkCapacity;
  }
  data['queryContent'] = queryContent;

  return {
    'querySetting': jsonEncode({
      'data': data,
      'pageSize': '$pageSize',
      'pageNumber': '$pageNumber',
      'order': order,
    }),
  };
}

/// The four submission shapes for adding a course. Returned by
/// [resolveAddParam] so the UI/monitor can display which one was used.
enum AddShape { plain, withTest, withBook, withTestAndBook }

/// Result of resolving an add request, including the shape used and the
/// human-readable fields that fed it.
class AddParamPlan {
  AddParamPlan({
    required this.form,
    required this.shape,
    required this.teachingClassId,
    this.testTeachingClassId,
    this.needBook,
    this.chooseVolunteer,
  });

  /// The form body to POST to volunteer.do.
  final Map<String, String> form;
  final AddShape shape;
  final String teachingClassId;
  final String? testTeachingClassId;
  final String? needBook;

  /// Volunteer grade sent in 预选 rounds, null in 正选/抢课 rounds.
  final String? chooseVolunteer;

  String get shapeLabel {
    final base = switch (shape) {
      AddShape.plain => '直接选课',
      AddShape.withTest => '含实验课选择',
      AddShape.withBook => '含教材选择',
      AddShape.withTestAndBook => '含实验课与教材',
    };
    return chooseVolunteer == null ? base : '$base，第$chooseVolunteer志愿';
  }
}

/// Low-level: builds the `addParam` form field.
///
/// [needBook] / [testTeachingClassId] are omitted when null/empty — mirroring
/// the frontend, which only appends them when the class actually requires them.
Map<String, String> buildAddVolunteerParam({
  required String studentCode,
  required String electiveBatchCode,
  required String teachingClassId,
  required String campus,
  required String teachingClassType,
  String isMajor = '1',
  String? needBook,
  String? testTeachingClassId,
  String? chooseVolunteer,
}) {
  final data = <String, dynamic>{
    'operationType': '1',
    'studentCode': studentCode,
    'electiveBatchCode': electiveBatchCode,
    'teachingClassId': teachingClassId,
    'isMajor': isMajor,
    'campus': campus,
    'teachingClassType': teachingClassType,
  };
  // Two official pages build this and their key order differs:
  //  - 正选/抢课 (grablessons.js): needBook, then testTeachingClassID
  //  - 预选/志愿 (curriculavariable.js): chooseVolunteer (always present, the
  //    volunteer grade "1" = 第一志愿), then testTeachingClassID, then needBook
  final hasBook = needBook != null && needBook.isNotEmpty;
  final hasTest = testTeachingClassId != null && testTeachingClassId.isNotEmpty;
  if (chooseVolunteer != null && chooseVolunteer.isNotEmpty) {
    data['chooseVolunteer'] = chooseVolunteer;
    if (hasTest) data['testTeachingClassID'] = testTeachingClassId;
    if (hasBook) data['needBook'] = needBook;
  } else {
    if (hasBook) data['needBook'] = needBook;
    if (hasTest) data['testTeachingClassID'] = testTeachingClassId;
  }
  return {
    'addParam': jsonEncode({'data': data})
  };
}

/// High-level: decides the correct submission shape from a [TeachingClass].
///
/// This is where selection-struct accuracy is enforced. Throws
/// [MissingSelectionError] when the class needs a test class or textbook string
/// that the caller has not supplied — the monitor must resolve these *before*
/// a seat opens, never at grab time.
AddParamPlan resolveAddParam({
  required TeachingClass tc,
  required String studentCode,
  required String electiveBatchCode,
  required String campus,
  required CourseKind kind,
  String? selectedTestTeachingClassId,
  String? bookSelection,
  bool textbookOrderingOpen = true,
  String? volunteerGrade,
}) {
  final needsTest = tc.hasTest;
  final needsBook = tc.hasBook && textbookOrderingOpen;

  final testId = selectedTestTeachingClassId?.isNotEmpty == true
      ? selectedTestTeachingClassId
      : (tc.testTeachingClassId.isNotEmpty ? tc.testTeachingClassId : null);

  if (needsTest && (testId == null || testId.isEmpty)) {
    throw MissingSelectionError(
      teachingClassId: tc.teachingClassId,
      reason: '该教学班包含实验课，必须先选择实验教学班 (testTeachingClassID)。',
    );
  }
  if (needsBook && (bookSelection == null || bookSelection.isEmpty)) {
    throw MissingSelectionError(
      teachingClassId: tc.teachingClassId,
      reason: '该教学班需要教材征订，必须先构造教材选择串 (needBook)。',
    );
  }

  final form = buildAddVolunteerParam(
    studentCode: studentCode,
    electiveBatchCode: electiveBatchCode,
    teachingClassId: tc.teachingClassId,
    campus: campus,
    teachingClassType: kind.code,
    isMajor: kind.isMajor,
    needBook: needsBook ? bookSelection : null,
    testTeachingClassId: needsTest ? testId : null,
    chooseVolunteer: volunteerGrade,
  );

  final shape = needsTest && needsBook
      ? AddShape.withTestAndBook
      : needsTest
          ? AddShape.withTest
          : needsBook
              ? AddShape.withBook
              : AddShape.plain;

  return AddParamPlan(
    form: form,
    shape: shape,
    teachingClassId: tc.teachingClassId,
    testTeachingClassId: needsTest ? testId : null,
    needBook: needsBook ? bookSelection : null,
    chooseVolunteer: volunteerGrade,
  );
}

/// Raised when a grab cannot be built because a required test-class or textbook
/// selection is missing. Surfaced to the user so they resolve it up front.
class MissingSelectionError implements Exception {
  MissingSelectionError({required this.teachingClassId, required this.reason});
  final String teachingClassId;
  final String reason;
  @override
  String toString() => 'MissingSelectionError($teachingClassId): $reason';
}

/// Builds the `deleteParam` form field for dropping a course.
Map<String, String> buildDeleteVolunteerParam({
  required String studentCode,
  required String electiveBatchCode,
  required String teachingClassId,
  String isMajor = '1',
}) {
  return {
    'deleteParam': jsonEncode({
      'data': {
        'operationType': '2',
        'studentCode': studentCode,
        'electiveBatchCode': electiveBatchCode,
        'teachingClassId': teachingClassId,
        'isMajor': isMajor,
      },
    }),
  };
}

/// Composes the textbook selection string for needBook / jcxx.
///
/// Per docs/api.notes.md getSelectJcxx(): ordered book: `<bookCode>`,
/// declined book: `<bookCode>-<reasonCode>`, joined by commas.
String buildBookSelection(List<BookChoice> choices) {
  for (final choice in choices) {
    if (!choice.order &&
        (choice.reasonCode.trim().isEmpty ||
            choice.reasonCode.trim() == '***')) {
      throw ArgumentError.value(
        choice.reasonCode,
        'reasonCode',
        '拒订教材 ${choice.bookCode} 必须选择有效原因',
      );
    }
  }
  return choices
      .map((c) => c.order ? c.bookCode : '${c.bookCode}-${c.reasonCode.trim()}')
      .join(',');
}

/// Resolves the experiment teaching-class ID across the response shapes seen
/// in the official API. Empty values must not shadow a later valid alias.
String? testTeachingClassIdFromRow(Map<String, dynamic> row) {
  for (final key in const [
    'testTeachingClassID',
    'teachingClassID',
    'teachingClassId'
  ]) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// One textbook decision within a class.
class BookChoice {
  BookChoice(
      {required this.bookCode, required this.order, this.reasonCode = ''});
  final String bookCode;

  /// true = order it, false = decline (then reasonCode is required).
  final bool order;
  final String reasonCode;
}

/// Params for the add/delete status poll (studentstatus.do).
Map<String, String> buildStudentStatusParam(String studentCode) =>
    {'studentCode': studentCode};

/// Params for student/xklcqr.do: confirms the selected round's notice.
Map<String, String> buildBatchConfirmParam({
  required String studentCode,
  required String electiveBatchCode,
}) =>
    {'studentCode': studentCode, 'electiveBatchCode': electiveBatchCode};

/// Params for the capacity-refresh endpoint.
Map<String, String> buildCapacityQuery({
  required String teachingClassId,
  required String studentCode,
  required String capacitySuffix,
  required String timestamp,
}) =>
    {
      'teachingClassId': teachingClassId,
      'capacitySuffix': capacitySuffix,
      'xh': studentCode,
      'timestamp': timestamp,
    };

/// Params for the can-choose pre-check.
Map<String, String> buildCanChooseQuery({
  required String studentCode,
  required String teachingClassId,
  required String electiveBatchCode,
  required String timestamp,
}) =>
    {
      'xh': studentCode,
      'jxbid': teachingClassId,
      'xklcdm': electiveBatchCode,
      'timestamp': timestamp,
    };

/// Params for the textbook-list query (queryxsjxbbook.do).
Map<String, String> buildTextbookQuery({
  required String studentCode,
  required String electiveBatchCode,
  required String teachingClassId,
}) =>
    {'xh': studentCode, 'xklcdm': electiveBatchCode, 'jxbid': teachingClassId};

/// Params for course-result / selected-course listing.
Map<String, String> buildSelectedCourseParam({
  required String studentCode,
  required String electiveBatchCode,
}) =>
    {'studentCode': studentCode, 'electiveBatchCode': electiveBatchCode};

// ---- Schedule / records / detail queries ----

/// Params for teachingTime.do / noArranged.do.
Map<String, String> buildScheduleQuery({
  required String studentCode,
  required String electiveBatchCode,
  required String timestamp,
}) =>
    {
      'studentCode': studentCode,
      'electiveBatchCode': electiveBatchCode,
      'timestamp': timestamp,
    };

/// Params for returnResults.do (drop log).
Map<String, String> buildReturnResultsQuery({
  required String studentCode,
  required String electiveBatchCode,
  required String timestamp,
}) =>
    {
      'studentCode': studentCode,
      'electiveBatchCode': electiveBatchCode,
      'timestamp': timestamp,
    };

/// Params for unsuccessful.do (落选课程).
///
/// `isRead` is mandatory: the server answers "Required String parameter
/// 'isRead' is not present" without it, and the official page always sends
/// "0" (unread) for the list.
Map<String, String> buildUnsuccessfulQuery({
  required String studentCode,
  required String electiveBatchCode,
  bool isRead = false,
}) =>
    {
      'isRead': isRead ? '1' : '0',
      'studentCode': studentCode,
      'electiveBatchCode': electiveBatchCode,
    };

/// Params for submit/unsuccessful.do: the 落选 rows' wids joined by commas,
/// as the official 落选课程提醒 popup posts them.
Map<String, String> buildSubmitUnsuccessfulQuery({
  required String studentCode,
  required List<String> wids,
}) =>
    {'wids': wids.join(','), 'studentCode': studentCode};

/// Params for queryjxb.do (教学班详情).
Map<String, String> buildTeachingClassDetailQuery({
  required String teachingClassId,
  required String electiveBatchCode,
}) =>
    {'jxbid': teachingClassId, 'xklcdm': electiveBatchCode};

/// Params for querykcxx.do (课程详情).
Map<String, String> buildCourseDetailQuery(String courseNumber) =>
    {'kch': courseNumber};

/// Builds the `queryParam` form field for course/volunteer.do (课程可选志愿等级).
/// curriculavariable.js also sends the category and the class id as `wid`.
Map<String, String> buildCourseVolunteerParam({
  required String studentCode,
  required String electiveBatchCode,
  required String courseNumber,
  String teachingClassType = '',
  String teachingClassId = '',
}) =>
    {
      'queryParam': jsonEncode({
        'data': {
          'studentCode': studentCode,
          'electiveBatchCode': electiveBatchCode,
          'courseNumber': courseNumber,
          if (teachingClassType.isNotEmpty)
            'teachingClassType': teachingClassType,
          if (teachingClassId.isNotEmpty) 'wid': teachingClassId,
        },
      }),
    };

// ---- Public-info queries ----

/// Params for notice/view.do (公告详情).
Map<String, String> buildNoticeViewQuery({
  required String wid,
  required String timestamp,
}) =>
    {'wid': wid, 'timestamp': timestamp};

/// Params for student/xkxf.do (学分信息).
///
/// [xklclx] is the elective-round type code (选课轮次类型). We thread the
/// batch's `electiveBatchType` through from [ElectiveBatch.batchType]; the
/// server accepts the same code it returns in `batchisopen.do`.
Map<String, String> buildCreditInfoParam({
  required String studentCode,
  required String electiveBatchCode,
  String xklclx = '',
}) =>
    {
      'xh': studentCode,
      'xklcdm': electiveBatchCode,
      if (xklclx.isNotEmpty) 'xklclx': xklclx,
    };

/// Params for the logout endpoint (logout.do).
Map<String, String> buildLogoutQuery({
  required String studentCode,
  required String timestamp,
}) =>
    {'studentNumber': studentCode, 'timestamp': timestamp};

// ---- Textbook write params ----

/// Params for textbook/addbook.do (订购教材).
///
/// Same request shape as the query — the server records the order against the
/// student × teaching class pair for this round.
Map<String, String> buildTextbookOrderParam({
  required String studentCode,
  required String electiveBatchCode,
  required String teachingClassId,
}) =>
    {'xh': studentCode, 'xklcdm': electiveBatchCode, 'jxbid': teachingClassId};

/// Params for textbook/modifybook.do (修改/退订教材).
///
/// [czlx] is the operation type: "0" = 退订, "1" = 修改. The [jcxx] string is
/// the same shape as `needBook` (see [buildBookSelection]).
Map<String, String> buildTextbookModifyParam({
  required String studentCode,
  required String electiveBatchCode,
  required String teachingClassId,
  required String jcxx,
  bool cancelAll = false,
}) =>
    {
      'xh': studentCode,
      'xklcdm': electiveBatchCode,
      'jxbid': teachingClassId,
      'jcxx': jcxx,
      'czlx': cancelAll ? '0' : '1',
    };

/// A built textbook selection: the jcxx string and the per-book choices.
class TextbookSelection {
  TextbookSelection(this.jcxx, this.choices);

  /// The `needBook`/`jcxx` string submitted to volunteer.do / modifybook.do.
  final String jcxx;
  final List<BookChoice> choices;

  /// Empty when no books were offered — caller should treat as "no textbook
  /// ordering needed" rather than a selection.
  bool get isEmpty => jcxx.isEmpty;
}
