/// Central configuration and endpoint paths for the NWAFU course system.
///
/// Endpoint paths are transcribed from the repo-root API research
/// (docs/api.notes.md, docs/api.coverage.md). Business calls hang off [apiBase].
library;

class Env {
  Env._();

  /// Business API host + prefix. All `/sys/...` paths append to this.
  static const String apiBase = 'https://bksxk.nwafu.edu.cn/xsxkapp';

  /// Default when nothing is stored. The user can override in Settings, since
  /// the school occasionally moves the deployment.
  static const String defaultOrigin = 'https://bksxk.nwafu.edu.cn';
}

/// All endpoints, grouped by concern. Paths only — the client prepends [Env.apiBase].
class Api {
  Api._();

  // ---- Auth / init ----
  static const vcodeToken = '/sys/xsxkapp/student/4/vcode.do';
  static const vcodeImage = '/sys/xsxkapp/student/vcode/image.do';
  static const checkLogin = '/sys/xsxkapp/student/check/login.do';
  static String studentInfo(String studentCode) => '/sys/xsxkapp/student/$studentCode.do';
  static const batch = '/sys/xsxkapp/elective/batch.do';
  static const batchIsOpen = '/sys/xsxkapp/elective/batchisopen.do';
  static const batchConfirm = '/sys/xsxkapp/student/xklcqr.do';
  static const dictionary = '/sys/xsxkapp/publicinfo/dictionary.do';
  static const sysParam = '/sys/xsxkapp/publicinfo/sysparam.do';
  static const onlineUsers = '/sys/xsxkapp/publicinfo/onlineUsers.do';
  static const guideMap = '/sys/xsxkapp/student/guideMap.do';
  static const creditInfo = '/sys/xsxkapp/student/xkxf.do';
  static const logout = '/sys/xsxkapp/student/logout.do';

  // ---- Course queries ----
  static const recommendedCourse = '/sys/xsxkapp/elective/recommendedCourse.do';
  static const programCourse = '/sys/xsxkapp/elective/programCourse.do';
  static const publicCourse = '/sys/xsxkapp/elective/publicCourse.do';
  static const queryCourse = '/sys/xsxkapp/elective/queryCourse.do';
  static const courseSearch = '/sys/xsxkapp/elective/course.do';

  // ---- Selected / records ----
  static const courseResult = '/sys/xsxkapp/elective/courseResult.do';
  static const returnResults = '/sys/xsxkapp/elective/returnResults.do';
  static const unsuccessful = '/sys/xsxkapp/elective/unsuccessful.do';
  static const studentQueue = '/sys/xsxkapp/elective/queryStudentQueue.do';

  // ---- Detail / validation ----
  static const teachingClassDetail = '/sys/xsxkapp/publicinfo/queryjxb.do';
  static const capacity = '/sys/xsxkapp/elective/teachingclass/capacity.do';
  static const canChoose = '/sys/xsxkapp/util/canchoose.do';
  static const testCourse = '/sys/xsxkapp/elective/testCourse.do';
  static const courseVolunteer = '/sys/xsxkapp/elective/course/volunteer.do';
  static const courseDetail = '/sys/xsxkapp/publicinfo/querykcxx.do';

  // ---- Write ops (state-changing) ----
  static const volunteer = '/sys/xsxkapp/elective/volunteer.do';
  static const deleteVolunteer = '/sys/xsxkapp/elective/deleteVolunteer.do';
  static const studentStatus = '/sys/xsxkapp/elective/studentstatus.do';

  // ---- Textbook ----
  static const textbookQuery = '/sys/xsxkapp/textbook/queryxsjxbbook.do';
  static const textbookAdd = '/sys/xsxkapp/textbook/addbook.do';
  static const textbookModify = '/sys/xsxkapp/textbook/modifybook.do';

  // ---- Schedule ----
  static const teachingTime = '/sys/xsxkapp/elective/teachingTime.do';
  static const noArranged = '/sys/xsxkapp/elective/noArranged.do';

  // ---- Info ----
  static const noticeList = '/sys/xsxkapp/publicinfo/notice.do';
  static const noticeView = '/sys/xsxkapp/publicinfo/notice/view.do';
  static const problemList = '/sys/xsxkapp/publicinfo/problem.do';
  static const volunteerGrade = '/sys/xsxkapp/publicinfo/volunteer.do';
}

/// The `teachingClassType` codes and the query endpoint each maps to.
enum CourseKind {
  tjkc('TJKC', '推荐课程', Api.recommendedCourse),
  fankc('FANKC', '方案内课程', Api.programCourse),
  fawkc('FAWKC', '方案外课程', Api.programCourse),
  xgxk('XGXK', '通识/公选课', Api.publicCourse),
  cxkc('CXKC', '重修课程', Api.programCourse),
  tykc('TYKC', '体育课程', Api.programCourse),
  fxkc('FXKC', '辅修课程', Api.programCourse),
  qxkc('QXKC', '全校课程', Api.queryCourse);

  const CourseKind(this.code, this.label, this.endpoint);

  /// The `teachingClassType` value sent in querySetting.
  final String code;

  /// Human-facing tab label.
  final String label;

  /// The POST endpoint this kind queries.
  final String endpoint;

  /// Foreign-minor (`FXKC`) queries send isMajor=0; everything else 1.
  String get isMajor => this == CourseKind.fxkc ? '0' : '1';

  /// Whole-school query (`QXKC`) omits checkConflict/checkCapacity.
  bool get includesChecks => this != CourseKind.qxkc;

  static CourseKind fromCode(String code) =>
      CourseKind.values.firstWhere((k) => k.code == code, orElse: () => CourseKind.fankc);
}
