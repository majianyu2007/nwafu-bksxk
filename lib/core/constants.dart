/// Central configuration and endpoint paths for the NWAFU course system.
///
/// Endpoint paths are transcribed from the api-branch research
/// (docs/api.notes.md, docs/api.runtime.md).
library;

/// Client version shown in diagnostics; keep in step with pubspec.yaml.
const String kAppVersion = '1.2.0';

class Env {
  Env._();

  /// Default when nothing is stored. The user can override in Settings, since
  /// the school occasionally moves the deployment.
  static const String defaultOrigin = 'https://bksxk.nwafu.edu.cn';
}

/// All endpoints, grouped by concern. Paths only — the client prepends
/// `<origin>/xsxkapp`.
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
  static const creditInfo = '/sys/xsxkapp/student/xkxf.do';
  static const logout = '/sys/xsxkapp/student/logout.do';

  // ---- Course queries ----
  static const recommendedCourse = '/sys/xsxkapp/elective/recommendedCourse.do';
  static const programCourse = '/sys/xsxkapp/elective/programCourse.do';
  static const publicCourse = '/sys/xsxkapp/elective/publicCourse.do';
  static const queryCourse = '/sys/xsxkapp/elective/queryCourse.do';

  // ---- Selected / records ----
  static const courseResult = '/sys/xsxkapp/elective/courseResult.do';

  /// 预选 rounds keep filed volunteers here instead of courseResult.do:
  /// volunteerResult.do = course rows with tcList (方案内 etc.),
  /// publicCourseResult.do = flat rows for 通识/公选 classes.
  static const volunteerResult = '/sys/xsxkapp/elective/volunteerResult.do';
  static const publicCourseResult =
      '/sys/xsxkapp/elective/publicCourseResult.do';
  static const returnResults = '/sys/xsxkapp/elective/returnResults.do';
  static const unsuccessful = '/sys/xsxkapp/elective/unsuccessful.do';

  /// Marks 落选 rows as read (the official popup's 确认 button).
  static const submitUnsuccessful =
      '/sys/xsxkapp/elective/submit/unsuccessful.do';

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
  static const publicInfo = '/sys/xsxkapp/publicinfo.do';
  static const noticeList = '/sys/xsxkapp/publicinfo/notice.do';
  static const noticeView = '/sys/xsxkapp/publicinfo/notice/view.do';
  static const volunteerGrade = '/sys/xsxkapp/publicinfo/volunteer.do';
}

/// The `teachingClassType` codes and the query endpoint each maps to.
enum CourseKind {
  tjkc('TJKC', '推荐课程', Api.recommendedCourse),
  fankc('FANKC', '方案内课程', Api.programCourse),
  fawkc('FAWKC', '方案外课程', Api.programCourse),
  xgxk('XGXK', '通识选修课', Api.publicCourse),
  cxkc('CXKC', '重修课程', Api.programCourse),
  tykc('TYKC', '体育课程', Api.programCourse),
  fxkc('FXKC', '辅修课程', Api.programCourse),
  qxkc('QXKC', '全校课程', Api.queryCourse);

  const CourseKind(this.code, this.label, this.endpoint);

  /// The `teachingClassType` value sent in querySetting.
  final String code;

  /// Fallback tab label; the server's sysparam.do `displayName*` wins.
  final String label;

  /// The POST endpoint this kind queries.
  final String endpoint;

  /// Foreign-minor (`FXKC`) queries send isMajor=0; everything else 1.
  String get isMajor => this == CourseKind.fxkc ? '0' : '1';

  /// Whole-school query (`QXKC`) omits checkConflict/checkCapacity.
  bool get includesChecks => this != CourseKind.qxkc;

  /// Whole-school rows are look-up only on the official page (no capacity,
  /// selection happens under the class's own category), and the list is
  /// thousands of rows, so it is paged server-side instead of loaded whole.
  bool get isBrowseOnly => this == CourseKind.qxkc;

  /// The sysparam.do key carrying this tab's official name.
  String get displayNameKey => switch (this) {
        CourseKind.tjkc => 'displayNameTJKC',
        CourseKind.fankc => 'displayNameFANKC',
        CourseKind.fawkc => 'displayNameFAWKC',
        CourseKind.xgxk => 'displayNameXGXK',
        CourseKind.cxkc => 'displayNameCXKC',
        CourseKind.tykc => 'displayNameTYKC',
        CourseKind.fxkc => 'displayNameFXKC',
        CourseKind.qxkc => 'displayNameALLKC',
      };

  static CourseKind fromCode(String code) =>
      CourseKind.values.firstWhere((k) => k.code == code, orElse: () => CourseKind.fankc);
}

/// Online (MOOC) courses are recognised by their course-number prefix, not by
/// `teachingMethod` (面授讲课+SPOC/MOOC is a blended classroom course). The
/// prefix is case-sensitive, as on the server. Verified on 2026-09-18: `ey`
/// rows are 超星尔雅 titles taught by the 教务处 account, `ZH` rows are 智慧树
/// titles taught by 网络教师; neither carries a time or a room.
const Map<String, String> kOnlineCoursePlatforms = {
  'ZH': '智慧树',
  'ey': '学习通',
  'yw': '知到',
};
