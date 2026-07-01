import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const outputPath = args.find((arg) => arg !== '--check') || 'docs/api.response-schemas.generated.json';
const manifestPath = 'docs/api.manifest.generated.json';

const envelopeFields = [
  'code',
  'msg',
  'data',
  'dataList',
  'totalCount',
  'map',
  'keyExpired',
  'timestamp',
];

const courseSummaryFields = [
  'credit',
  'courseUrl',
  'majorFlag',
  'courseFlag',
  'replaceCourseName',
  'courseNumber',
  'courseName',
  'courseNatureName',
  'retakeType',
  'retakeTypeDetail',
  'departmentName',
  'campusName',
  'replaceCourseNumber',
  'number',
  'selected',
  'tcList',
  'type',
  'typeName',
  'hours',
  'wid',
];

const teachingClassFields = [
  'teachingClassID',
  'courseNumber',
  'courseName',
  'courseIndex',
  'teacherName',
  'teachingPlace',
  'classCapacity',
  'numberOfSelected',
  'isFull',
  'isConflict',
  'conflictDesc',
  'hasTest',
  'isTest',
  'testTeachingClassID',
  'needOrderBook',
  'needBook',
  'hasBook',
  'chooseVolunteer',
  'isChoose',
  'capacitySuffix',
  'numberOfFirstVolunteer',
  'engpCode',
  'engpName',
  'sportCode',
  'sportName',
  'courseNature',
  'courseNatureName',
  'courseType',
  'courseTypeName',
  'departmentName',
  'campus',
  'campusName',
  'hours',
  'credit',
  'wid',
];

const selectedCourseExtraFields = [
  'studentCode',
  'isMajor',
  'trainingCode',
  'deleteOperateTime',
  'teachingClassType',
  'studentName',
  'canDelete',
  'selectStatus',
  'learnType',
  'noOccupyCapacity',
  'deleteOperateType',
  'deleteOperateTypeName',
  'deleteOperatePersonName',
  'operateIP',
  'isConfirm',
  'capacityType',
  'comment',
];

const xkxfDataFields = [
  'electiveIsOpen',
  'levelTeaching',
  'studentTag',
  'collegeName',
  'departmentName',
  'grade',
  'schoolClass',
  'schoolClassName',
  'totalCredit',
  'getCredit',
  'needCredit',
  'campus',
  'campusName',
  'college',
  'department',
  'gender',
  'trainingLevel',
  'studentType',
  'majorTrainingCode',
  'minorTrainingCode',
  'limitElective',
  'majorName',
  'electiveBatch',
  'electiveBatchList',
  'limitElectiveList',
  'noSelectReason',
  'teachCampus',
  'expElectiveBatchList',
  'noSearchCj',
  'code',
  'name',
  'wid',
];

const teacherFields = [
  'NO',
  'NAME',
  'SEX',
  'COUNTRY',
  'JOB_TITLE',
  'ADMINISTRATION_TITLE',
  'FACULTY_NAME',
  'COMPANY_NAME',
  'TUTOR_TYPE',
  'TYPENAME',
  'START_DATE',
  'END_DATE',
  'UNDERGRADUATE_TOTAL_TEACH_TIME',
  'GRADUATE_TOTAL_TEACH_TIME',
  'WORKS_TEXTBOOK_TOTAL_CNT',
  'TEACH_AWARDS_TOTAL_CNT',
  'TEACH_THESIS_TOTAL_CNT',
  'SCIENTIFIC_AWARDS_TOTAL_CNT',
  'wid',
];

const noticeFields = ['title', 'publishTime', 'timeDescription', 'filename', 'content', 'wid'];
const problemFields = ['title', 'publishTime', 'timeDescription', 'content', 'serialNumber', 'wid'];
const volunteerGradeFields = ['grade', 'isUse', 'name', 'wid'];
const scoreFields = ['schoolTermName', 'courseNumber', 'courseName', 'credit', 'score', 'retakeTypeName'];
const bookFields = ['wid'];
const canChooseDataFields = [
  'studentCode',
  'isMajor',
  'electiveBatchCode',
  'queryContent',
  'checkCapacity',
  'courseNumber',
  'campus',
  'teachingClassType',
  'checkConflict',
  'reasonList',
  'wid',
];

function endpointKey(method, endpoint) {
  return `${method.toUpperCase()} ${endpoint}`;
}

function envelopeSchema({
  availability = 'runtime-field-summary',
  dataFields,
  dataListItemFields,
  mapKind,
  notes,
} = {}) {
  return {
    availability,
    envelopeFields,
    ...(dataFields ? { dataFields } : {}),
    ...(dataListItemFields ? { dataListItemFields } : {}),
    ...(mapKind ? { mapKind } : {}),
    ...(notes ? { notes } : {}),
  };
}

function writeNotExecuted(notes = 'State-changing endpoint; request construction is documented, but no real response was captured.') {
  return {
    availability: 'write-not-executed',
    envelopeFields,
    notes,
  };
}

function staticOnly(notes = 'Static call site and request construction are documented; runtime response body is not captured.') {
  return {
    availability: 'static-only',
    envelopeFields,
    notes,
  };
}

const schemas = new Map([
  [endpointKey('GET', '/sys/xsxkapp/elective/batch.do'), envelopeSchema({
    dataListItemFields: ['code', 'name', 'batchType', 'canSelect', 'beginTime', 'endTime', 'tacticCode', 'schoolTermName', 'weekRange'],
  })],
  [endpointKey('POST', '/sys/xsxkapp/elective/batchisopen.do'), envelopeSchema({ notes: '`msg` is observed as `1` when the batch is open.' })],
  [endpointKey('GET', '/sys/xsxkapp/student/4/vcode.do'), staticOnly('Returns a captcha token object; static/login flow only.')],
  [endpointKey('GET', '/sys/xsxkapp/student/vcode/image.do'), { availability: 'binary', contentType: 'image/*', notes: 'Captcha image bytes.' }],
  [endpointKey('GET', '/sys/xsxkapp/student/check/login.do'), staticOnly('Successful response includes a session token; raw login response is not persisted.')],
  [endpointKey('GET', '/sys/xsxkapp/student/<studentCode>.do'), envelopeSchema({ dataFields: xkxfDataFields })],
  [endpointKey('POST', '/sys/xsxkapp/student/xklcqr.do'), writeNotExecuted()],
  [endpointKey('GET', '/sys/xsxkapp/student/guideMap.do'), envelopeSchema({ notes: 'Observed `msg=已读引导页` for an already-read guide page.' })],
  [endpointKey('POST', '/sys/xsxkapp/student/guideMap.do'), writeNotExecuted('Marks guide page as read; not executed for response capture.')],
  [endpointKey('GET', '/sys/xsxkapp/student/register.do'), writeNotExecuted('Registration endpoint; not executed for response capture.')],
  [endpointKey('GET', '/sys/xsxkapp/student/logout.do'), writeNotExecuted('Logout endpoint; not executed for response capture.')],
  [endpointKey('GET', '/sys/xsxkapp/student/authlogout.do'), writeNotExecuted('Auth logout endpoint; not executed for response capture.')],

  [endpointKey('GET', '/sys/xsxkapp/publicinfo.do'), envelopeSchema({
    dataFields: ['celebrityFamousList', 'consultMethod', 'noticeList', 'commonProblemList', 'stopInfo', 'wid'],
  })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/dictionary.do'), envelopeSchema({ mapKind: 'dictionary object keyed by dictionary category' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/sysparam.do'), envelopeSchema({ dataFields: ['needBook', 'displayCjMenu', 'xgxkQueryTitle', 'useList', 'kclbNotDisplay', 'displayMajorFlag', 'isSplitRetake'] })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/onlineUsers.do'), envelopeSchema({ notes: 'Online user count/status endpoint; exact body varies by deployment.' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/volunteer.do'), envelopeSchema({ dataListItemFields: volunteerGradeFields })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/fx/nj.do'), envelopeSchema({ notes: 'Filter dictionary; observed code=1.' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/fx/yx.do'), envelopeSchema({ notes: 'Filter dictionary; observed code=1.' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/fx/zy.do'), envelopeSchema({ notes: 'Filter dictionary; observed code=1.' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/zx/nj.do'), envelopeSchema({ notes: 'Filter dictionary; observed code=1.' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/zx/yx.do'), envelopeSchema({ notes: 'Filter dictionary; observed code=1.' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/zx/zy.do'), envelopeSchema({ notes: '`msg` can be a large JSON string dictionary.' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/notice.do'), envelopeSchema({ dataListItemFields: noticeFields })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/notice/view.do'), envelopeSchema({ dataFields: noticeFields })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/problem.do'), envelopeSchema({ dataListItemFields: problemFields })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/celebrityfamous.do'), envelopeSchema({ dataListItemFields: ['englishContent', 'content', 'author', 'wid'] })],

  [endpointKey('POST', '/sys/xsxkapp/elective/recommendedCourse.do'), envelopeSchema({ dataListItemFields: courseSummaryFields, mapKind: 'course row tcList contains teaching class cards' })],
  [endpointKey('POST', '/sys/xsxkapp/elective/programCourse.do'), envelopeSchema({ dataListItemFields: courseSummaryFields, mapKind: 'course row tcList contains teaching class cards' })],
  [endpointKey('POST', '/sys/xsxkapp/elective/publicCourse.do'), envelopeSchema({ dataListItemFields: courseSummaryFields })],
  [endpointKey('POST', '/sys/xsxkapp/elective/queryCourse.do'), envelopeSchema({ dataListItemFields: teachingClassFields, notes: 'All-school query returns flattened teaching-class rows.' })],
  [endpointKey('POST', '/sys/xsxkapp/elective/testCourse.do'), envelopeSchema({ dataListItemFields: courseSummaryFields, mapKind: 'textbook selection map keyed by opaque ids' })],
  [endpointKey('POST', '/sys/xsxkapp/elective/course/kcssfa.do'), envelopeSchema({ dataListItemFields: courseSummaryFields })],
  [endpointKey('GET', '/sys/xsxkapp/elective/course.do'), {
    availability: 'static-residual-nonjson',
    notes: 'Static queryCourse() wrapper sends GET, but runtime business JSON was observed on POST for the same path.',
  }],
  [endpointKey('POST', '/sys/xsxkapp/elective/course.do'), envelopeSchema({ dataListItemFields: courseSummaryFields, notes: 'Runtime JSON endpoint is POST even though static wrapper says GET.' })],
  [endpointKey('GET', '/sys/xsxkapp/elective/course/volunteer.do'), envelopeSchema({ dataListItemFields: volunteerGradeFields })],
  [endpointKey('GET', '/sys/xsxkapp/elective/volunteered.do'), {
    availability: 'static-residual-404',
    httpStatus: 404,
    notes: 'Static function exists, but current deployment returned HTML 404; selected-volunteer UI uses courseResult.do.',
  }],

  [endpointKey('GET', '/sys/xsxkapp/elective/courseResult.do'), envelopeSchema({ dataListItemFields: [...teachingClassFields, ...selectedCourseExtraFields] })],
  [endpointKey('GET', '/sys/xsxkapp/elective/returnResults.do'), envelopeSchema({ dataListItemFields: [...teachingClassFields, ...selectedCourseExtraFields], notes: 'Observed empty dataList in current capture.' })],
  [endpointKey('GET', '/sys/xsxkapp/elective/unsuccessful.do'), envelopeSchema({ dataListItemFields: [...teachingClassFields, 'isRead'], notes: 'Observed empty dataList in current capture.' })],
  [endpointKey('GET', '/sys/xsxkapp/elective/queryStudentQueue.do'), envelopeSchema({ notes: 'Observed empty dataList in current capture.' })],
  [endpointKey('GET', '/sys/xsxkapp/elective/teachingTime.do'), envelopeSchema({ dataListItemFields: teachingClassFields, notes: 'Scheduled timetable rows.' })],
  [endpointKey('GET', '/sys/xsxkapp/elective/noArranged.do'), envelopeSchema({ dataListItemFields: teachingClassFields, notes: 'Courses without arranged timetable slots.' })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/queryjxb.do'), envelopeSchema({ dataFields: teachingClassFields })],
  [endpointKey('GET', '/sys/xsxkapp/elective/teachingclass/capacity.do'), envelopeSchema({ dataFields: teachingClassFields })],
  [endpointKey('GET', '/sys/xsxkapp/util/canchoose.do'), envelopeSchema({ dataFields: canChooseDataFields })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/querykcxx.do'), envelopeSchema({ dataFields: ['courseNumber', 'courseName', 'credit', 'hours', 'courseNatureName', 'departmentName', 'courseUrl', 'wid'] })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/queryjzg.do'), envelopeSchema({ dataFields: teacherFields })],
  [endpointKey('GET', '/sys/xsxkapp/publicinfo/queryjzgphoto.do'), { availability: 'binary-or-empty', contentType: 'image/*', notes: 'Teacher photo endpoint.' }],
  [endpointKey('POST', '/sys/xsxkapp/student/xkxf.do'), envelopeSchema({ dataFields: xkxfDataFields })],
  [endpointKey('POST', '/sys/xsxkapp/student/xscj.do'), envelopeSchema({ dataListItemFields: scoreFields, notes: 'Current runtime returned code=0 because score menu was not open.' })],
  [endpointKey('POST', '/sys/xsxkapp/textbook/queryxsjxbbook.do'), envelopeSchema({ dataListItemFields: bookFields, notes: '`wid` may contain JSON-encoded textbook fields such as ISBN, SM, ZZZ, JCBH, SFDG.' })],

  [endpointKey('POST', '/sys/xsxkapp/elective/volunteer.do'), writeNotExecuted()],
  [endpointKey('GET', '/sys/xsxkapp/elective/deleteVolunteer.do'), writeNotExecuted()],
  [endpointKey('POST', '/sys/xsxkapp/elective/studentstatus.do'), staticOnly('Polled after add/delete; success/failure status is documented from static flow, real post-operation response not captured.')],
  [endpointKey('POST', '/sys/xsxkapp/textbook/addbook.do'), writeNotExecuted()],
  [endpointKey('POST', '/sys/xsxkapp/textbook/modifybook.do'), writeNotExecuted()],
  [endpointKey('GET', '/sys/xsxkapp/elective/submit/unsuccessful.do'), writeNotExecuted()],
]);

const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const missing = manifest.endpoints
  .map((endpoint) => endpointKey(endpoint.method, endpoint.endpoint))
  .filter((key) => !schemas.has(key));

if (missing.length > 0) {
  console.error('Missing response schemas:');
  for (const key of missing) console.error(`- ${key}`);
  process.exit(1);
}

const responseSchemas = manifest.endpoints.map((endpoint) => ({
  id: endpoint.id,
  section: endpoint.section,
  status: endpoint.status,
  method: endpoint.method,
  endpoint: endpoint.endpoint,
  stateChanging: endpoint.stateChanging,
  description: endpoint.description,
  response: schemas.get(endpointKey(endpoint.method, endpoint.endpoint)),
}));

const output = {
  schemaVersion: 1,
  generatedFrom: [manifestPath, 'docs/api.runtime.md', 'docs/api.notes.md'],
  endpointCount: responseSchemas.length,
  availabilityLegend: {
    'runtime-field-summary': 'Fields were observed or summarized from runtime probes.',
    'envelope-only': 'Only the common response envelope is known.',
    binary: 'Endpoint returns binary content.',
    'binary-or-empty': 'Endpoint can return binary content or an empty/fallback response.',
    'static-only': 'Static call site is known, but response body has not been captured.',
    'write-not-executed': 'State-changing endpoint; not executed against the real system.',
    'static-residual-404': 'Static reference exists, but runtime probe returned 404.',
    'static-residual-nonjson': 'Static reference exists, but runtime behavior is not the business JSON endpoint.',
  },
  responseSchemas,
};

const serialized = `${JSON.stringify(output, null, 2)}\n`;

if (process.argv.includes('--check')) {
  const current = await readFile(outputPath, 'utf8');
  if (current !== serialized) {
    console.error(`${outputPath} is stale. Run: npm run response-schemas`);
    process.exit(1);
  }
  console.log(`Response schema check passed: ${responseSchemas.length} schemas are current.`);
} else {
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, serialized);
  console.log(`Wrote ${outputPath} with ${responseSchemas.length} response schemas.`);
}
