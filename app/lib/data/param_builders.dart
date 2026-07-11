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
  });

  /// The form body to POST to volunteer.do.
  final Map<String, String> form;
  final AddShape shape;
  final String teachingClassId;
  final String? testTeachingClassId;
  final String? needBook;

  String get shapeLabel {
    switch (shape) {
      case AddShape.plain:
        return '直接选课';
      case AddShape.withTest:
        return '含实验课选择';
      case AddShape.withBook:
        return '含教材选择';
      case AddShape.withTestAndBook:
        return '含实验课与教材';
    }
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
  if (needBook != null && needBook.isNotEmpty) data['needBook'] = needBook;
  if (testTeachingClassId != null && testTeachingClassId.isNotEmpty) {
    data['testTeachingClassID'] = testTeachingClassId;
  }
  return {'addParam': jsonEncode({'data': data})};
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
String buildBookSelection(List<BookChoice> choices) =>
    choices.map((c) => c.order ? c.bookCode : '${c.bookCode}-${c.reasonCode}').join(',');

/// One textbook decision within a class.
class BookChoice {
  BookChoice({required this.bookCode, required this.order, this.reasonCode = ''});
  final String bookCode;

  /// true = order it, false = decline (then reasonCode is required).
  final bool order;
  final String reasonCode;
}

/// Params for the add/delete status poll (studentstatus.do).
Map<String, String> buildStudentStatusParam(String studentCode) => {'studentCode': studentCode};

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
