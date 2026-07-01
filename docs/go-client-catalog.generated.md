# Go 客户端字段目录

这份生成物把 `client.contract.generated.json` 转换成 Go 实现视角：每个端点的请求字段、表单内 JSON 路径、响应字段、执行策略和建议模型分组。

## 统计

| 项目 | 值 |
| --- | --- |
| `byImplementationStatus` | `{"ready-from-runtime":43,"request-ready-response-static":3,"serialize-only":10,"static-residual-nonjson":1,"static-residual-404":1}` |
| `byExecutionPolicy` | `{"read-only-callable":48,"serialize-only":10}` |
| `bySection` | `{"登录与初始化":12,"公共信息与字典":15,"课程列表与查询":10,"已选、课表与详情":15,"状态变更":6}` |
| `requestFieldPathCount` | `355` |
| `responseFieldPathCount` | `1032` |
| `sharedFieldNameCount` | `178` |

## 实现状态说明

- `ready-from-runtime`：请求构造和响应字段均有运行期证据或二进制类型证据。
- `request-ready-response-static`：请求构造已定位，响应只保留静态说明，后续实现要宽松解码。
- `serialize-only`：状态变更接口，只在本地构造请求，不用真实系统执行响应捕获。
- `static-residual-*`：静态残留或当前部署不走的路径，保留兼容处理。

## 端点实现清单

| ID | 方法 | 端点 | 策略 | 实现状态 | Go 模型提示 |
| --- | --- | --- | --- | --- | --- |
| `get_elective_batch_do` | `GET` | `/sys/xsxkapp/elective/batch.do` | `read-only-callable` | `ready-from-runtime` | ElectiveBatch model |
| `post_elective_batchisopen_do` | `POST` | `/sys/xsxkapp/elective/batchisopen.do` | `read-only-callable` | `ready-from-runtime` | ElectiveBatch model |
| `get_student_4_vcode_do` | `GET` | `/sys/xsxkapp/student/4/vcode.do` | `read-only-callable` | `request-ready-response-static` | Envelope plus endpoint-specific fields |
| `get_student_vcode_image_do` | `GET` | `/sys/xsxkapp/student/vcode/image.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_student_check_login_do` | `GET` | `/sys/xsxkapp/student/check/login.do` | `read-only-callable` | `request-ready-response-static` | Envelope plus endpoint-specific fields |
| `get_student_studentcode_do` | `GET` | `/sys/xsxkapp/student/<studentCode>.do` | `read-only-callable` | `ready-from-runtime` | StudentSession/StudentCredit models |
| `post_student_xklcqr_do` | `POST` | `/sys/xsxkapp/student/xklcqr.do` | `serialize-only` | `serialize-only` | Envelope plus endpoint-specific fields |
| `get_student_guidemap_do` | `GET` | `/sys/xsxkapp/student/guideMap.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `post_student_guidemap_do` | `POST` | `/sys/xsxkapp/student/guideMap.do` | `serialize-only` | `serialize-only` | Envelope plus endpoint-specific fields |
| `get_student_register_do` | `GET` | `/sys/xsxkapp/student/register.do` | `serialize-only` | `serialize-only` | Envelope plus endpoint-specific fields |
| `get_student_logout_do` | `GET` | `/sys/xsxkapp/student/logout.do` | `serialize-only` | `serialize-only` | Envelope plus endpoint-specific fields |
| `get_student_authlogout_do` | `GET` | `/sys/xsxkapp/student/authlogout.do` | `serialize-only` | `serialize-only` | Envelope plus endpoint-specific fields |
| `get_publicinfo_do` | `GET` | `/sys/xsxkapp/publicinfo.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_dictionary_do` | `GET` | `/sys/xsxkapp/publicinfo/dictionary.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_sysparam_do` | `GET` | `/sys/xsxkapp/publicinfo/sysparam.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_onlineusers_do` | `GET` | `/sys/xsxkapp/publicinfo/onlineUsers.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_volunteer_do` | `GET` | `/sys/xsxkapp/publicinfo/volunteer.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_fx_nj_do` | `GET` | `/sys/xsxkapp/publicinfo/fx/nj.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_fx_yx_do` | `GET` | `/sys/xsxkapp/publicinfo/fx/yx.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_fx_zy_do` | `GET` | `/sys/xsxkapp/publicinfo/fx/zy.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_zx_nj_do` | `GET` | `/sys/xsxkapp/publicinfo/zx/nj.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_zx_yx_do` | `GET` | `/sys/xsxkapp/publicinfo/zx/yx.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_zx_zy_do` | `GET` | `/sys/xsxkapp/publicinfo/zx/zy.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_notice_do` | `GET` | `/sys/xsxkapp/publicinfo/notice.do` | `read-only-callable` | `ready-from-runtime` | PublicInfo models |
| `get_publicinfo_notice_view_do` | `GET` | `/sys/xsxkapp/publicinfo/notice/view.do` | `read-only-callable` | `ready-from-runtime` | PublicInfo models |
| `get_publicinfo_problem_do` | `GET` | `/sys/xsxkapp/publicinfo/problem.do` | `read-only-callable` | `ready-from-runtime` | PublicInfo models |
| `get_publicinfo_celebrityfamous_do` | `GET` | `/sys/xsxkapp/publicinfo/celebrityfamous.do` | `read-only-callable` | `ready-from-runtime` | PublicInfo models |
| `post_elective_recommendedcourse_do` | `POST` | `/sys/xsxkapp/elective/recommendedCourse.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `post_elective_programcourse_do` | `POST` | `/sys/xsxkapp/elective/programCourse.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `post_elective_publiccourse_do` | `POST` | `/sys/xsxkapp/elective/publicCourse.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `post_elective_querycourse_do` | `POST` | `/sys/xsxkapp/elective/queryCourse.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `post_elective_testcourse_do` | `POST` | `/sys/xsxkapp/elective/testCourse.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `post_elective_course_kcssfa_do` | `POST` | `/sys/xsxkapp/elective/course/kcssfa.do` | `read-only-callable` | `ready-from-runtime` | Course/TeachingClass models |
| `get_elective_course_do` | `GET` | `/sys/xsxkapp/elective/course.do` | `read-only-callable` | `static-residual-nonjson` | Envelope plus endpoint-specific fields |
| `post_elective_course_do` | `POST` | `/sys/xsxkapp/elective/course.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_elective_course_volunteer_do` | `GET` | `/sys/xsxkapp/elective/course/volunteer.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_elective_volunteered_do` | `GET` | `/sys/xsxkapp/elective/volunteered.do` | `read-only-callable` | `static-residual-404` | Envelope plus endpoint-specific fields |
| `get_elective_courseresult_do` | `GET` | `/sys/xsxkapp/elective/courseResult.do` | `read-only-callable` | `ready-from-runtime` | Course/TeachingClass models |
| `get_elective_returnresults_do` | `GET` | `/sys/xsxkapp/elective/returnResults.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_elective_unsuccessful_do` | `GET` | `/sys/xsxkapp/elective/unsuccessful.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_elective_querystudentqueue_do` | `GET` | `/sys/xsxkapp/elective/queryStudentQueue.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_elective_teachingtime_do` | `GET` | `/sys/xsxkapp/elective/teachingTime.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_elective_noarranged_do` | `GET` | `/sys/xsxkapp/elective/noArranged.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_queryjxb_do` | `GET` | `/sys/xsxkapp/publicinfo/queryjxb.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_elective_teachingclass_capacity_do` | `GET` | `/sys/xsxkapp/elective/teachingclass/capacity.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_util_canchoose_do` | `GET` | `/sys/xsxkapp/util/canchoose.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_querykcxx_do` | `GET` | `/sys/xsxkapp/publicinfo/querykcxx.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `get_publicinfo_queryjzg_do` | `GET` | `/sys/xsxkapp/publicinfo/queryjzg.do` | `read-only-callable` | `ready-from-runtime` | Teacher model |
| `get_publicinfo_queryjzgphoto_do` | `GET` | `/sys/xsxkapp/publicinfo/queryjzgphoto.do` | `read-only-callable` | `ready-from-runtime` | Teacher model |
| `post_student_xkxf_do` | `POST` | `/sys/xsxkapp/student/xkxf.do` | `read-only-callable` | `ready-from-runtime` | StudentSession/StudentCredit models |
| `post_student_xscj_do` | `POST` | `/sys/xsxkapp/student/xscj.do` | `read-only-callable` | `ready-from-runtime` | Envelope plus endpoint-specific fields |
| `post_textbook_queryxsjxbbook_do` | `POST` | `/sys/xsxkapp/textbook/queryxsjxbbook.do` | `read-only-callable` | `ready-from-runtime` | Textbook model |
| `post_elective_volunteer_do` | `POST` | `/sys/xsxkapp/elective/volunteer.do` | `serialize-only` | `serialize-only` | Envelope plus endpoint-specific fields |
| `get_elective_deletevolunteer_do` | `GET` | `/sys/xsxkapp/elective/deleteVolunteer.do` | `serialize-only` | `serialize-only` | Envelope plus endpoint-specific fields |
| `post_elective_studentstatus_do` | `POST` | `/sys/xsxkapp/elective/studentstatus.do` | `read-only-callable` | `request-ready-response-static` | Envelope plus endpoint-specific fields |
| `post_textbook_addbook_do` | `POST` | `/sys/xsxkapp/textbook/addbook.do` | `serialize-only` | `serialize-only` | Textbook model |
| `post_textbook_modifybook_do` | `POST` | `/sys/xsxkapp/textbook/modifybook.do` | `serialize-only` | `serialize-only` | Textbook model |
| `get_elective_submit_unsuccessful_do` | `GET` | `/sys/xsxkapp/elective/submit/unsuccessful.do` | `serialize-only` | `serialize-only` | Envelope plus endpoint-specific fields |

## 高频字段索引

| 字段 | 请求次数 | 响应次数 | 位置 |
| --- | --- | --- | --- |
| `timestamp` | 31 | 54 | `query`, `response.envelope` |
| `data` | 19 | 54 | `formJson`, `queryJson`, `response.envelope`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson`, `variant:FXKC:bodyJson`, `variant:TYKC:bodyJson` |
| `map` | 0 | 58 | `response.envelope`, `response.map` |
| `code` | 0 | 57 | `response.data`, `response.dataList[]`, `response.envelope` |
| `dataList` | 0 | 54 | `response.envelope` |
| `keyExpired` | 0 | 54 | `response.envelope` |
| `msg` | 0 | 54 | `response.envelope` |
| `totalCount` | 0 | 54 | `response.envelope` |
| `token` | 42 | 0 | `header` |
| `studentCode` | 34 | 3 | `form`, `formJson`, `pathParams`, `query`, `queryJson`, `response.data`, `response.dataList[]`, `variant:CXKC:bodyJson` |
| `electiveBatchCode` | 29 | 1 | `form`, `formJson`, `query`, `queryJson`, `response.data`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson` |
| `campus` | 17 | 11 | `form`, `formJson`, `queryJson`, `response.data`, `response.dataList[]`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson` |
| `wid` | 1 | 27 | `query`, `response.data`, `response.dataList[]` |
| `isMajor` | 18 | 3 | `form`, `formJson`, `queryJson`, `response.data`, `response.dataList[]`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson` |
| `teachingClassType` | 17 | 3 | `form`, `formJson`, `queryJson`, `response.data`, `response.dataList[]`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson` |
| `courseNumber` | 2 | 17 | `formJson`, `queryJson`, `response.data`, `response.dataList[]` |
| `departmentName` | 0 | 17 | `response.data`, `response.dataList[]` |
| `campusName` | 0 | 16 | `response.data`, `response.dataList[]` |
| `courseName` | 0 | 16 | `response.data`, `response.dataList[]` |
| `credit` | 0 | 16 | `response.data`, `response.dataList[]` |
| `courseNatureName` | 0 | 15 | `response.data`, `response.dataList[]` |
| `hours` | 0 | 15 | `response.data`, `response.dataList[]` |
| `pageNumber` | 14 | 0 | `formJson`, `query`, `queryJson`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson`, `variant:FXKC:bodyJson`, `variant:TYKC:bodyJson` |
| `pageSize` | 14 | 0 | `formJson`, `query`, `queryJson`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson`, `variant:FXKC:bodyJson`, `variant:TYKC:bodyJson` |
| `checkCapacity` | 11 | 1 | `form`, `formJson`, `queryJson`, `response.data`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson`, `variant:FXKC:bodyJson` |
| `checkConflict` | 11 | 1 | `form`, `formJson`, `queryJson`, `response.data`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson`, `variant:FXKC:bodyJson` |
| `queryContent` | 11 | 1 | `formJson`, `queryJson`, `response.data`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson`, `variant:FXKC:bodyJson`, `variant:TYKC:bodyJson` |
| `querySetting` | 12 | 0 | `form`, `query`, `variant:CXKC:body`, `variant:FANKC:body`, `variant:FAWKC:body`, `variant:FXKC:body`, `variant:TYKC:body` |
| `needBook` | 2 | 9 | `response.data`, `response.dataList[]`, `variant:withBook:formJson`, `variant:withTestAndBook:formJson` |
| `order` | 11 | 0 | `formJson`, `queryJson`, `variant:CXKC:bodyJson`, `variant:FANKC:bodyJson`, `variant:FAWKC:bodyJson`, `variant:FXKC:bodyJson`, `variant:TYKC:bodyJson` |
| `testTeachingClassID` | 2 | 8 | `response.data`, `response.dataList[]`, `variant:withTest:formJson`, `variant:withTestAndBook:formJson` |
| `capacitySuffix` | 1 | 8 | `query`, `response.data`, `response.dataList[]` |
| `chooseVolunteer` | 0 | 8 | `response.data`, `response.dataList[]` |
| `classCapacity` | 0 | 8 | `response.data`, `response.dataList[]` |
| `conflictDesc` | 0 | 8 | `response.data`, `response.dataList[]` |
| `courseIndex` | 0 | 8 | `response.data`, `response.dataList[]` |
| `courseNature` | 0 | 8 | `response.data`, `response.dataList[]` |
| `courseType` | 0 | 8 | `response.data`, `response.dataList[]` |
| `courseTypeName` | 0 | 8 | `response.data`, `response.dataList[]` |
| `engpCode` | 0 | 8 | `response.data`, `response.dataList[]` |
| `engpName` | 0 | 8 | `response.data`, `response.dataList[]` |
| `hasBook` | 0 | 8 | `response.data`, `response.dataList[]` |
| `hasTest` | 0 | 8 | `response.data`, `response.dataList[]` |
| `isChoose` | 0 | 8 | `response.data`, `response.dataList[]` |
| `isConflict` | 0 | 8 | `response.data`, `response.dataList[]` |
| `isFull` | 0 | 8 | `response.data`, `response.dataList[]` |
| `isTest` | 0 | 8 | `response.data`, `response.dataList[]` |
| `needOrderBook` | 0 | 8 | `response.data`, `response.dataList[]` |
| `numberOfFirstVolunteer` | 0 | 8 | `response.data`, `response.dataList[]` |
| `numberOfSelected` | 0 | 8 | `response.data`, `response.dataList[]` |
| `sportCode` | 0 | 8 | `response.data`, `response.dataList[]` |
| `sportName` | 0 | 8 | `response.data`, `response.dataList[]` |
| `teacherName` | 0 | 8 | `response.data`, `response.dataList[]` |
| `teachingClassID` | 0 | 8 | `response.data`, `response.dataList[]` |
| `teachingPlace` | 0 | 8 | `response.data`, `response.dataList[]` |
| `courseUrl` | 0 | 7 | `response.data`, `response.dataList[]` |
| `number` | 1 | 6 | `query`, `response.dataList[]` |
| `teachingClassId` | 7 | 0 | `formJson`, `query`, `queryJson`, `variant:withBook:formJson`, `variant:withTest:formJson`, `variant:withTestAndBook:formJson`, `variant:withoutTestOrBook:formJson` |
| `xklcdm` | 7 | 0 | `form`, `query` |
| `courseFlag` | 0 | 6 | `response.dataList[]` |

## 失败项

_None._

