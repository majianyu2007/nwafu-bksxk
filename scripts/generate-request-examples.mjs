import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

import {
  buildAddVolunteerParam,
  buildAddVolunteerParamFromTeachingClass,
  buildAuthLogoutQuery,
  buildBasicCourseRequest,
  buildBatchConfirmParam,
  buildBatchIsOpenParam,
  buildBatchQuery,
  buildCanChooseQuery,
  buildCapacityQuery,
  buildCelebrityFamousQuery,
  buildCourseDetailQuery,
  buildCoursePlanQuery,
  buildCourseQueryForType,
  buildCourseVolunteerQuery,
  buildCurriculumQuery,
  buildDeleteVolunteerParam,
  buildGuideMapMarkReadQuery,
  buildGuideMapQuery,
  buildHomePublicInfoQuery,
  buildLogoutQuery,
  buildNoticeListQuery,
  buildNoticeViewQuery,
  buildProblemListQuery,
  buildRegisterQuery,
  buildReturnResultsQuery,
  buildScoreQuery,
  buildSelectedCourseParam,
  buildStudentInfoQuery,
  buildStudentStatusParam,
  buildTeacherDetailQuery,
  buildTeachingClassDetailQuery,
  buildTestCourseQuery,
  buildTextbookAddParam,
  buildTextbookModifyParam,
  buildTextbookQuery,
  buildUnsuccessfulQuery,
  buildVolunteeredQuery,
  buildVolunteerGradeQuery,
} from './request-builders.mjs';

const manifestPath = 'docs/api.manifest.generated.json';
const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const outputPath = args.find((arg) => arg !== '--check') || 'docs/api.requests.generated.json';

function key(method, endpoint) {
  return `${method.toUpperCase()} ${endpoint}`;
}

function request({
  pathParams = {},
  query = {},
  form = {},
  headers = ['token'],
  contentType,
  variants,
  notes,
} = {}) {
  return {
    headers,
    ...(contentType ? { contentType } : {}),
    ...(Object.keys(pathParams).length ? { pathParams } : {}),
    ...(Object.keys(query).length ? { query } : {}),
    ...(Object.keys(form).length ? { form } : {}),
    ...(variants ? { variants } : {}),
    ...(notes ? { notes } : {}),
  };
}

function formPost(form, extra = {}) {
  return request({
    form,
    contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
    ...extra,
  });
}

const addVolunteerVariants = [
  {
    name: 'withoutTestOrBook',
    form: buildAddVolunteerParam(),
  },
  {
    name: 'withTest',
    form: buildAddVolunteerParamFromTeachingClass({
      teachingClass: {
        teachingClassID: '<teachingClassId>',
        hasTest: '1',
        testTeachingClassID: '<selectedTestTeachingClassID>',
        hasBook: '0',
      },
    }),
  },
  {
    name: 'withBook',
    form: buildAddVolunteerParamFromTeachingClass({
      teachingClass: {
        teachingClassID: '<teachingClassId>',
        hasTest: '0',
        hasBook: '1',
      },
      bookSelection: '<bookCode-or-bookCode-reason,...>',
    }),
  },
  {
    name: 'withTestAndBook',
    form: buildAddVolunteerParamFromTeachingClass({
      teachingClass: {
        teachingClassID: '<teachingClassId>',
        hasTest: '1',
        testTeachingClassID: '<selectedTestTeachingClassID>',
        hasBook: '1',
      },
      bookSelection: '<bookCode-or-bookCode-reason,...>',
    }),
  },
];

const programCourseVariants = ['FANKC', 'FAWKC', 'CXKC', 'TYKC', 'FXKC']
  .map((type) => ({
    name: type,
    ...buildCourseQueryForType(type),
  }));

const examplesByKey = new Map([
  [key('GET', '/sys/xsxkapp/elective/batch.do'), request({ query: buildBatchQuery(), headers: [] })],
  [key('POST', '/sys/xsxkapp/elective/batchisopen.do'), formPost(buildBatchIsOpenParam(), { headers: [] })],
  [key('GET', '/sys/xsxkapp/student/4/vcode.do'), request({ query: { timestamp: '<timestamp>' }, headers: [] })],
  [key('GET', '/sys/xsxkapp/student/vcode/image.do'), request({ query: { vtoken: '<vtoken>' }, headers: [] })],
  [key('GET', '/sys/xsxkapp/student/check/login.do'), request({
    query: {
      timestrap: '<timestamp>',
      loginName: '<studentCode>',
      loginPwd: '<password>',
      verifyCode: '<captcha>',
      vtoken: '<vtoken>',
    },
    headers: [],
  })],
  [key('GET', '/sys/xsxkapp/student/<studentCode>.do'), request({
    pathParams: { studentCode: '<studentCode>' },
    query: { timestamp: buildStudentInfoQuery().timestamp },
  })],
  [key('POST', '/sys/xsxkapp/student/xklcqr.do'), formPost(buildBatchConfirmParam())],
  [key('GET', '/sys/xsxkapp/student/guideMap.do'), request({ query: buildGuideMapQuery() })],
  [key('POST', '/sys/xsxkapp/student/guideMap.do'), request({ query: buildGuideMapMarkReadQuery() })],
  [key('GET', '/sys/xsxkapp/student/register.do'), request({ query: buildRegisterQuery(), headers: [] })],
  [key('GET', '/sys/xsxkapp/student/logout.do'), request({ query: buildLogoutQuery() })],
  [key('GET', '/sys/xsxkapp/student/authlogout.do'), request({ query: buildAuthLogoutQuery(), headers: [] })],

  [key('GET', '/sys/xsxkapp/publicinfo.do'), request({ query: buildHomePublicInfoQuery(), headers: [] })],
  [key('GET', '/sys/xsxkapp/publicinfo/dictionary.do'), request({ query: { timestamp: '<timestamp>' } })],
  [key('GET', '/sys/xsxkapp/publicinfo/sysparam.do'), request({ query: { timestamp: '<timestamp>', _: '<timestamp>' } })],
  [key('GET', '/sys/xsxkapp/publicinfo/onlineUsers.do'), request({ query: { timestamp: '<timestamp>' }, headers: [] })],
  [key('GET', '/sys/xsxkapp/publicinfo/volunteer.do'), request({ query: buildVolunteerGradeQuery() })],
  [key('GET', '/sys/xsxkapp/publicinfo/fx/nj.do'), request({ query: { timestamp: '<timestamp>' } })],
  [key('GET', '/sys/xsxkapp/publicinfo/fx/yx.do'), request({ query: { timestamp: '<timestamp>' } })],
  [key('GET', '/sys/xsxkapp/publicinfo/fx/zy.do'), request({ query: { timestamp: '<timestamp>' } })],
  [key('GET', '/sys/xsxkapp/publicinfo/zx/nj.do'), request({ query: { timestamp: '<timestamp>' } })],
  [key('GET', '/sys/xsxkapp/publicinfo/zx/yx.do'), request({ query: { timestamp: '<timestamp>' } })],
  [key('GET', '/sys/xsxkapp/publicinfo/zx/zy.do'), request({ query: { timestamp: '<timestamp>' } })],
  [key('GET', '/sys/xsxkapp/publicinfo/notice.do'), request({ query: { timestamp: '<timestamp>', ...buildNoticeListQuery() }, headers: [] })],
  [key('GET', '/sys/xsxkapp/publicinfo/notice/view.do'), request({ query: { timestamp: '<timestamp>', ...buildNoticeViewQuery() }, headers: [] })],
  [key('GET', '/sys/xsxkapp/publicinfo/problem.do'), request({ query: { timestamp: '<timestamp>', ...buildProblemListQuery() }, headers: [] })],
  [key('GET', '/sys/xsxkapp/publicinfo/celebrityfamous.do'), request({ query: buildCelebrityFamousQuery(), headers: [] })],

  [key('POST', '/sys/xsxkapp/elective/recommendedCourse.do'), formPost(buildCourseQueryForType('TJKC').body)],
  [key('POST', '/sys/xsxkapp/elective/programCourse.do'), formPost(buildCourseQueryForType('FANKC').body, { variants: programCourseVariants })],
  [key('POST', '/sys/xsxkapp/elective/publicCourse.do'), formPost(buildCourseQueryForType('XGXK').body)],
  [key('POST', '/sys/xsxkapp/elective/queryCourse.do'), formPost(buildCourseQueryForType('QXKC').body)],
  [key('POST', '/sys/xsxkapp/elective/testCourse.do'), formPost(buildTestCourseQuery())],
  [key('POST', '/sys/xsxkapp/elective/course/kcssfa.do'), formPost(buildCoursePlanQuery())],
  [key('GET', '/sys/xsxkapp/elective/course.do'), request({
    query: { timestamp: '<timestamp>', ...buildBasicCourseRequest().body },
    notes: 'Static queryCourse() wrapper; runtime business JSON uses POST for the same path.',
  })],
  [key('POST', '/sys/xsxkapp/elective/course.do'), formPost(buildBasicCourseRequest().body, { notes: 'Static wrapper says GET; runtime JSON endpoint is POST.' })],
  [key('GET', '/sys/xsxkapp/elective/course/volunteer.do'), request({ query: buildCourseVolunteerQuery() })],
  [key('GET', '/sys/xsxkapp/elective/volunteered.do'), request({ query: buildVolunteeredQuery(), notes: 'Static residual; current deployment returned 404 during runtime probe.' })],

  [key('GET', '/sys/xsxkapp/elective/courseResult.do'), request({ query: { timestamp: '<timestamp>', ...buildSelectedCourseParam() } })],
  [key('GET', '/sys/xsxkapp/elective/returnResults.do'), request({ query: { timestamp: '<timestamp>', ...buildReturnResultsQuery() } })],
  [key('GET', '/sys/xsxkapp/elective/unsuccessful.do'), request({ query: buildUnsuccessfulQuery() })],
  [key('GET', '/sys/xsxkapp/elective/queryStudentQueue.do'), request({ query: buildSelectedCourseParam() })],
  [key('GET', '/sys/xsxkapp/elective/teachingTime.do'), request({ query: buildCurriculumQuery() })],
  [key('GET', '/sys/xsxkapp/elective/noArranged.do'), request({ query: buildCurriculumQuery() })],
  [key('GET', '/sys/xsxkapp/publicinfo/queryjxb.do'), request({ query: buildTeachingClassDetailQuery() })],
  [key('GET', '/sys/xsxkapp/elective/teachingclass/capacity.do'), request({ query: buildCapacityQuery() })],
  [key('GET', '/sys/xsxkapp/util/canchoose.do'), request({ query: buildCanChooseQuery() })],
  [key('GET', '/sys/xsxkapp/publicinfo/querykcxx.do'), request({ query: buildCourseDetailQuery(), headers: [] })],
  [key('GET', '/sys/xsxkapp/publicinfo/queryjzg.do'), request({ query: buildTeacherDetailQuery(), headers: [] })],
  [key('GET', '/sys/xsxkapp/publicinfo/queryjzgphoto.do'), request({ query: buildTeacherDetailQuery(), headers: [] })],
  [key('POST', '/sys/xsxkapp/student/xkxf.do'), formPost({ xh: '<studentCode>', xklcdm: '<batchCode>', xklclx: '<batchType>' })],
  [key('POST', '/sys/xsxkapp/student/xscj.do'), formPost(buildScoreQuery())],
  [key('POST', '/sys/xsxkapp/textbook/queryxsjxbbook.do'), formPost(buildTextbookQuery())],

  [key('POST', '/sys/xsxkapp/elective/volunteer.do'), formPost(buildAddVolunteerParam(), { variants: addVolunteerVariants })],
  [key('GET', '/sys/xsxkapp/elective/deleteVolunteer.do'), request({ query: { timestamp: '<timestamp>', ...buildDeleteVolunteerParam() } })],
  [key('POST', '/sys/xsxkapp/elective/studentstatus.do'), formPost(buildStudentStatusParam())],
  [key('POST', '/sys/xsxkapp/textbook/addbook.do'), formPost(buildTextbookAddParam())],
  [key('POST', '/sys/xsxkapp/textbook/modifybook.do'), formPost(buildTextbookModifyParam())],
  [key('GET', '/sys/xsxkapp/elective/submit/unsuccessful.do'), request({ query: { wids: '<wid,...>', studentCode: '<studentCode>' } })],
]);

const manifest = JSON.parse(await readFile('docs/api.manifest.generated.json', 'utf8'));
const manifestKeys = new Set(manifest.endpoints.map((endpoint) => key(endpoint.method, endpoint.endpoint)));
const missing = [...manifestKeys].filter((endpointKey) => !examplesByKey.has(endpointKey)).sort();
const extra = [...examplesByKey.keys()].filter((endpointKey) => !manifestKeys.has(endpointKey)).sort();

if (missing.length > 0 || extra.length > 0) {
  if (missing.length > 0) {
    console.error('Missing request examples:');
    for (const endpointKey of missing) console.error(`- ${endpointKey}`);
  }
  if (extra.length > 0) {
    console.error('Request examples not present in manifest:');
    for (const endpointKey of extra) console.error(`- ${endpointKey}`);
  }
  process.exit(1);
}

const requests = manifest.endpoints.map((endpoint) => ({
  id: endpoint.id,
  section: endpoint.section,
  status: endpoint.status,
  method: endpoint.method,
  endpoint: endpoint.endpoint,
  stateChanging: endpoint.stateChanging,
  description: endpoint.description,
  request: examplesByKey.get(key(endpoint.method, endpoint.endpoint)),
}));

const output = {
  schemaVersion: 1,
  generatedFrom: ['docs/api.manifest.generated.json', 'scripts/request-builders.mjs'],
  requestCount: requests.length,
  requests,
};

const serialized = `${JSON.stringify(output, null, 2)}\n`;

if (checkOnly) {
  const current = await readFile(outputPath, 'utf8');
  if (current !== serialized) {
    console.error(`${outputPath} is stale. Run: npm run api-requests`);
    process.exit(1);
  }
  console.log(`Request examples check passed: ${requests.length} examples are current.`);
} else {
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, serialized);
  console.log(`Wrote ${outputPath} with ${requests.length} request examples.`);
}
