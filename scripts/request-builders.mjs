export function buildCourseQuery({
  studentCode = '<studentCode>',
  campus = '<campus>',
  electiveBatchCode = '<batchCode>',
  teachingClassType = 'TJKC',
  checkConflict = '2',
  checkCapacity = '2',
  queryContent = '',
  pageSize = '10',
  pageNumber = '0',
  order = '',
  isMajor = '1',
} = {}) {
  const data = {
    studentCode,
    campus,
    electiveBatchCode,
    isMajor,
    teachingClassType,
  };

  if (checkConflict != null) data.checkConflict = checkConflict;
  if (checkCapacity != null) data.checkCapacity = checkCapacity;
  data.queryContent = queryContent;

  return {
    querySetting: JSON.stringify({
      data,
      pageSize: String(pageSize),
      pageNumber: String(pageNumber),
      order,
    }),
  };
}

export function buildCourseQueryForType(type, overrides = {}) {
  const defaultsByType = {
    TJKC: { endpoint: '/sys/xsxkapp/elective/recommendedCourse.do', teachingClassType: 'TJKC' },
    FANKC: { endpoint: '/sys/xsxkapp/elective/programCourse.do', teachingClassType: 'FANKC' },
    FAWKC: { endpoint: '/sys/xsxkapp/elective/programCourse.do', teachingClassType: 'FAWKC' },
    XGXK: { endpoint: '/sys/xsxkapp/elective/publicCourse.do', teachingClassType: 'XGXK' },
    CXKC: { endpoint: '/sys/xsxkapp/elective/programCourse.do', teachingClassType: 'CXKC' },
    TYKC: { endpoint: '/sys/xsxkapp/elective/programCourse.do', teachingClassType: 'TYKC' },
    FXKC: { endpoint: '/sys/xsxkapp/elective/programCourse.do', teachingClassType: 'FXKC', isMajor: '0' },
    QXKC: {
      endpoint: '/sys/xsxkapp/elective/queryCourse.do',
      teachingClassType: 'QXKC',
      checkConflict: null,
      checkCapacity: null,
    },
  };
  const config = defaultsByType[type] || defaultsByType.TJKC;
  return {
    endpoint: config.endpoint,
    method: 'POST',
    body: buildCourseQuery({ ...config, ...overrides }),
  };
}

export function buildCourseQueryPagesForType(type, {
  pageSize = '10',
  pageCount = '1',
  ...overrides
} = {}) {
  const count = Number(pageCount);
  if (!Number.isInteger(count) || count < 1) {
    throw new Error('pageCount must be a positive integer');
  }

  return Array.from({ length: count }, (_, pageNumber) =>
    buildCourseQueryForType(type, {
      ...overrides,
      pageSize,
      pageNumber: String(pageNumber),
    }));
}

export function buildAddVolunteerParam({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
  teachingClassId = '<teachingClassId>',
  campus = '<campus>',
  teachingClassType = '<teachingClassType>',
  isMajor = '1',
  needBook,
  testTeachingClassID,
} = {}) {
  const data = {
    operationType: '1',
    studentCode,
    electiveBatchCode,
    teachingClassId,
    isMajor,
    campus,
    teachingClassType,
  };

  if (needBook != null && needBook !== '') data.needBook = String(needBook);
  if (testTeachingClassID != null && testTeachingClassID !== '') data.testTeachingClassID = String(testTeachingClassID);

  return {
    addParam: JSON.stringify({ data }),
  };
}

export function buildAddVolunteerParamFromTeachingClass({
  teachingClass = {
    teachingClassID: '<teachingClassId>',
    hasTest: '0',
    testTeachingClassID: '',
    hasBook: '0',
  },
  bookSelection,
  selectedTestTeachingClassID,
  ...context
} = {}) {
  const hasTest = String(teachingClass.hasTest ?? '') === '1';
  const hasBook = String(teachingClass.hasBook ?? '') === '1';
  const teachingClassId = teachingClass.teachingClassID || teachingClass.teachingClassId || '<teachingClassId>';

  return buildAddVolunteerParam({
    ...context,
    teachingClassId,
    testTeachingClassID: selectedTestTeachingClassID ?? (hasTest ? (teachingClass.testTeachingClassID || '<selectedTestTeachingClassID>') : undefined),
    needBook: bookSelection ?? (hasBook ? '<bookSelection>' : undefined),
  });
}

export function buildDeleteVolunteerParam({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
  teachingClassId = '<teachingClassId>',
  isMajor = '1',
} = {}) {
  return {
    deleteParam: JSON.stringify({
      data: {
        operationType: '2',
        studentCode,
        electiveBatchCode,
        teachingClassId,
        isMajor,
      },
    }),
  };
}

export function buildStudentStatusParam({ studentCode = '<studentCode>' } = {}) {
  return { studentCode };
}

export function buildBatchQuery() {
  return { timestamp: '<timestamp>' };
}

export function buildBatchIsOpenParam({ electiveBatchCode = '<batchCode>' } = {}) {
  return { xklcdm: electiveBatchCode };
}

export function buildBatchConfirmParam({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
} = {}) {
  return { electiveBatchCode, studentCode };
}

export function buildStudentInfoQuery({ studentCode = '<studentCode>' } = {}) {
  return { pathStudentCode: studentCode, timestamp: '<timestamp>' };
}

export function buildGuideMapQuery({ studentCode = '<studentCode>' } = {}) {
  return { timestamp: '<timestamp>', studentCode };
}

export function buildGuideMapMarkReadQuery({ studentCode = '<studentCode>' } = {}) {
  return { studentCode };
}

export function buildHomePublicInfoQuery({
  pageSize = '10',
  pageNumber = '1',
} = {}) {
  return { timestamp: '<timestamp>', pageSize: String(pageSize), pageNumber: String(pageNumber) };
}

export function buildCelebrityFamousQuery() {
  return { timestamp: '<timestamp>' };
}

export function buildVolunteerGradeQuery() {
  return { timestamp: '<timestamp>' };
}

export function buildDepartmentFilterQuery({
  scope = 'zx',
  dimension = 'nj',
} = {}) {
  return { endpoint: `/sys/xsxkapp/publicinfo/${scope}/${dimension}.do`, timestamp: '<timestamp>' };
}

export function buildBasicCourseQuery({
  teachingClassType = 'FANKC',
  ...overrides
} = {}) {
  return buildCourseQuery({ teachingClassType, ...overrides });
}

export function buildBasicCourseRequest(options = {}) {
  return {
    endpoint: '/sys/xsxkapp/elective/course.do',
    method: 'POST',
    body: buildBasicCourseQuery(options),
  };
}

export function buildCourseVolunteerQuery({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
  courseNumber = '<courseNumber>',
} = {}) {
  return {
    queryParam: JSON.stringify({
      data: { studentCode, electiveBatchCode, courseNumber },
    }),
    timestamp: '<timestamp>',
  };
}

export function buildVolunteeredQuery({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
} = {}) {
  return {
    timestamp: '<timestamp>',
    studentCode,
    electiveBatchCode,
  };
}

export function buildCoursePlanQuery({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
  courseNumber = '<courseNumber>',
  pageSize = '10',
  pageNumber = '0',
} = {}) {
  return {
    querySetting: JSON.stringify({
      data: { studentCode, electiveBatchCode, courseNumber },
      pageSize: String(pageSize),
      pageNumber: String(pageNumber),
    }),
  };
}

export function buildTestCourseQuery({
  teachingClassId = '<teachingClassId>',
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
  campus = '<campus>',
  teachingClassType = '<teachingClassType>',
  isMajor = '1',
  checkCapacity = '0',
  checkConflict = '0',
  ...params
} = {}) {
  return {
    jxbid: teachingClassId,
    electiveBatchCode,
    studentCode,
    isMajor,
    teachingClassType,
    campus,
    checkCapacity,
    checkConflict,
    ...params,
  };
}

export function buildSelectedCourseParam({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
} = {}) {
  return { studentCode, electiveBatchCode };
}

export function buildTeachingClassDetailQuery({
  electiveBatchCode = '<batchCode>',
  teachingClassId = '<teachingClassId>',
} = {}) {
  return { xklcdm: electiveBatchCode, jxbid: teachingClassId };
}

export function buildCapacityQuery({
  teachingClassId = '<teachingClassId>',
  studentCode = '<studentCode>',
  capacitySuffix = '<capacitySuffix>',
} = {}) {
  return { teachingClassId, capacitySuffix, xh: studentCode, timestamp: '<timestamp>' };
}

export function buildCanChooseQuery({
  studentCode = '<studentCode>',
  teachingClassId = '<teachingClassId>',
  electiveBatchCode = '<batchCode>',
} = {}) {
  return { xh: studentCode, jxbid: teachingClassId, xklcdm: electiveBatchCode, timestamp: '<timestamp>' };
}

export function buildUnsuccessfulQuery({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
  isRead = '1',
} = {}) {
  return { isRead, studentCode, electiveBatchCode };
}

export function buildReturnResultsQuery({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
} = {}) {
  return { studentCode, electiveBatchCode };
}

export function buildTextbookQuery({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
  teachingClassId = '<teachingClassId>',
} = {}) {
  return { xh: studentCode, xklcdm: electiveBatchCode, jxbid: teachingClassId };
}

export function buildTextbookAddParam(options = {}) {
  return buildTextbookQuery(options);
}

export function buildTextbookModifyParam({
  jcxx = '<bookCode-or-bookCode-reason,...>',
  operationType = '1',
  ...rest
} = {}) {
  return { ...buildTextbookQuery(rest), jcxx, czlx: operationType };
}

export function buildCurriculumQuery({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
} = {}) {
  return { timestamp: '<timestamp>', studentCode, electiveBatchCode };
}

export function buildCourseDetailQuery({ courseNumber = '<courseNumber>' } = {}) {
  return { kch: courseNumber };
}

export function buildTeacherDetailQuery({ teacherCode = '<teacherCode>' } = {}) {
  return { jsh: teacherCode };
}

export function buildScoreQuery({
  studentCode = '<studentCode>',
  electiveBatchCode = '<batchCode>',
} = {}) {
  return { electiveBatchCode, studentCode };
}

export function buildNoticeListQuery({
  pageSize = '10',
  pageNumber = '0',
} = {}) {
  return { pageSize: String(pageSize), pageNumber: String(pageNumber) };
}

export function buildNoticeViewQuery({ wid = '<noticeWid>' } = {}) {
  return { wid };
}

export function buildProblemListQuery() {
  return {};
}

export function buildRegisterQuery({ uid = '<studentOrCasNumber>' } = {}) {
  return { number: uid };
}

export function buildLogoutQuery({ studentCode = '<studentCode>' } = {}) {
  return { timestamp: '<timestamp>', studentNumber: studentCode };
}

export function buildAuthLogoutQuery() {
  return { timestamp: '<timestamp>' };
}

export function buildRequestExamples() {
  return {
    batch: buildBatchQuery(),
    batchIsOpen: buildBatchIsOpenParam(),
    batchConfirm: buildBatchConfirmParam(),
    studentInfo: buildStudentInfoQuery(),
    guideMap: buildGuideMapQuery(),
    guideMapMarkRead: buildGuideMapMarkReadQuery(),
    homePublicInfo: buildHomePublicInfoQuery(),
    celebrityFamous: buildCelebrityFamousQuery(),
    volunteerGrade: buildVolunteerGradeQuery(),
    departmentFilters: {
      fxNj: buildDepartmentFilterQuery({ scope: 'fx', dimension: 'nj' }),
      fxYx: buildDepartmentFilterQuery({ scope: 'fx', dimension: 'yx' }),
      fxZy: buildDepartmentFilterQuery({ scope: 'fx', dimension: 'zy' }),
      zxNj: buildDepartmentFilterQuery({ scope: 'zx', dimension: 'nj' }),
      zxYx: buildDepartmentFilterQuery({ scope: 'zx', dimension: 'yx' }),
      zxZy: buildDepartmentFilterQuery({ scope: 'zx', dimension: 'zy' }),
    },
    courseQuery: buildCourseQuery(),
    courseQueriesByType: Object.fromEntries(
      ['TJKC', 'FANKC', 'FAWKC', 'XGXK', 'CXKC', 'TYKC', 'FXKC', 'QXKC'].map((type) => [type, buildCourseQueryForType(type)]),
    ),
    programCoursePagedExample: buildCourseQueryPagesForType('FANKC', {
      pageSize: '10',
      pageCount: '1',
      queryContent: '',
    }),
    programCourseSingleLargePageExample: buildCourseQueryForType('FANKC', {
      pageSize: '1000',
      pageNumber: '0',
      queryContent: '',
    }),
    allSchoolPagedExample: buildCourseQueryPagesForType('QXKC', {
      pageSize: '1000',
      pageCount: '1',
      queryContent: '',
    }),
    allSchoolSingleLargePageExample: buildCourseQueryForType('QXKC', {
      pageSize: '10000',
      pageNumber: '0',
      queryContent: '',
    }),
    basicCourse: buildBasicCourseRequest(),
    courseVolunteer: buildCourseVolunteerQuery(),
    volunteered: buildVolunteeredQuery(),
    coursePlan: buildCoursePlanQuery(),
    testCourse: buildTestCourseQuery(),
    selectedCourse: buildSelectedCourseParam(),
    teachingClassDetail: buildTeachingClassDetailQuery(),
    capacity: buildCapacityQuery(),
    canChoose: buildCanChooseQuery(),
    unsuccessful: buildUnsuccessfulQuery(),
    returnResults: buildReturnResultsQuery(),
    textbookQuery: buildTextbookQuery(),
    textbookAdd: buildTextbookAddParam(),
    textbookModify: buildTextbookModifyParam(),
    curriculumTeachingTime: buildCurriculumQuery(),
    curriculumNoArranged: buildCurriculumQuery(),
    courseDetail: buildCourseDetailQuery(),
    teacherDetail: buildTeacherDetailQuery(),
    score: buildScoreQuery(),
    noticeList: buildNoticeListQuery(),
    noticeView: buildNoticeViewQuery(),
    problemList: buildProblemListQuery(),
    register: buildRegisterQuery(),
    logout: buildLogoutQuery(),
    authLogout: buildAuthLogoutQuery(),
    addVolunteer: buildAddVolunteerParam(),
    addVolunteerWithTest: buildAddVolunteerParamFromTeachingClass({
      teachingClass: {
        teachingClassID: '<teachingClassId>',
        hasTest: '1',
        testTeachingClassID: '<selectedTestTeachingClassID>',
        hasBook: '0',
      },
    }),
    addVolunteerWithBook: buildAddVolunteerParamFromTeachingClass({
      teachingClass: {
        teachingClassID: '<teachingClassId>',
        hasTest: '0',
        hasBook: '1',
      },
      bookSelection: '<bookCode-or-bookCode-reason,...>',
    }),
    addVolunteerWithTestAndBook: buildAddVolunteerParamFromTeachingClass({
      teachingClass: {
        teachingClassID: '<teachingClassId>',
        hasTest: '1',
        testTeachingClassID: '<selectedTestTeachingClassID>',
        hasBook: '1',
      },
      bookSelection: '<bookCode-or-bookCode-reason,...>',
    }),
    deleteVolunteer: buildDeleteVolunteerParam(),
    studentStatus: buildStudentStatusParam(),
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const examples = buildRequestExamples();
  console.log(JSON.stringify(examples, null, 2));
}
