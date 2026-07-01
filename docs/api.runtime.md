# BKSXK 运行期 API 字段摘要

生成依据：2026-06-30 登录后在 `grablessons.do` 页面内通过 MCP Playwright 调用页面已有查询函数。只调用查询接口，未执行 `volunteer.do`、`deleteVolunteer.do`、教材订退等写操作。

## 课程列表

通用响应包：

```json
{
  "dataList": [],
  "keyExpired": false,
  "totalCount": 0,
  "msg": "",
  "code": "1",
  "map": {},
  "timestamp": 0
}
```

| 类型 | 接口 | 本次 code | totalCount | 行结构 |
| --- | --- | ---: | ---: | --- |
| `TJKC` 推荐课程 | `POST /sys/xsxkapp/elective/recommendedCourse.do` | `1` | 11 | 课程行，含 `tcList` |
| `FANKC` 方案内 | `POST /sys/xsxkapp/elective/programCourse.do` | `1` | 15 | 课程行，含 `tcList` |
| `FAWKC` 方案外 | `POST /sys/xsxkapp/elective/programCourse.do` | `0` | - | 本次空结果 |
| `XGXK` 公选课 | `POST /sys/xsxkapp/elective/publicCourse.do` | `0` | - | 本次空结果 |
| `CXKC` 重修 | `POST /sys/xsxkapp/elective/programCourse.do` | `0` | - | 本次空结果 |
| `TYKC` 体育 | `POST /sys/xsxkapp/elective/programCourse.do` | `1` | 1 | 课程行，含 `tcList` |
| `FXKC` 辅修 | `POST /sys/xsxkapp/elective/programCourse.do` | `0` | - | 本次空结果 |
| `QXKC` 全校课程 | `POST /sys/xsxkapp/elective/queryCourse.do` | `1` | 6879 | 教学班行 |

课程行字段：

```text
credit, courseUrl, majorFlag, courseFlag, replaceCourseName, courseNumber,
courseName, courseNatureName, retakeType, retakeTypeDetail, departmentName,
campusName, replaceCourseNumber, number, selected, tcList, type, typeName,
hours, wid
```

教学班行字段：

```text
capacityOfFemale, numberOfMale, numberOfFemale, schoolClassMap,
schoolClassMapDetail, recommendSchoolClass, islimitKind, limitKindList,
teachingTimeList, isRetakeClass, sameCourseNumber, teacherNameList,
courseGroupCode, isFull, examTime, courseSectionCode, courseSection,
numberOfSelected, preCourseNumber, preCourseName, preCourseNumber2,
preCourseName2, preCourseCheckType, mainClassCapacity, nonMainClassCapacity,
mainElectiveNumber, nonMainElectiveNumber, teachingMethod, capacitySuffix,
courseUrl, majorFlag, courseFlag, canSelect, levelTeaching, department,
teachCampus, engpCode, engpName, needOrderBook, limitGender, capacityOfMale,
preCourseMustPass, operationType, electiveBatchCode, teachingClassID,
classCapacity, credit, replaceCourseName, retakeInfo, chooseVolunteer,
isChoose, courseNumber, courseName, courseIndex, teacherName, teachingPlace,
teachingPlaceHide, sportCode, preSportCode, sportName, courseNature,
courseNatureName, courseType, courseTypeName, numberOfFirstVolunteer,
isConflict, conflictDesc, hasTest, isTest, testTeachingClassID, retakeType,
retakeTypeDetail, inQuene, hasBook, examType, hasGradeCapacity, conflictHour,
conflictHourRate, departmentName, campus, campusName, schoolTerm,
publicCourseType, publicCourseTypeName, needBook, extInfo, hours, wid
```

### 分页与完整拉取实测

课程列表的 `querySetting.pageNumber` 从 `0` 开始，`pageSize` 可放大。本次对方案内课程 `FANKC`、空关键词查询实测：

| `pageSize` | `pageNumber` | `totalCount` | `dataList.length` |
| ---: | ---: | ---: | ---: |
| 10 | 0 | 15 | 10 |
| 100 | 0 | 15 | 15 |
| 1000 | 0 | 15 | 15 |

因此当前方案内课程可以用 `pageSize >= totalCount` 在第一页一次取完。Go 客户端仍应保留分页循环：先尝试较大 `pageSize`，再根据 `totalCount` 判断是否继续请求后续页。

同日对全校课程 `QXKC` 空关键词继续做只读验证：

| `pageSize` | `pageNumber` | `totalCount` | `dataList.length` | 响应体大小 | 耗时 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1000 | 0 | 6879 | 1000 | 约 2.4 MB | 约 12 s |
| 10000 | 0 | 6879 | 6879 | 约 17.9 MB | 约 13 s |

因此 `queryCourse.do` 可以通过大 `pageSize` 一次拿到全校课程完整教学班列表；但它返回教学班平铺行，不是按课程聚合的列表。客户端如果需要课程维度，应自行按 `courseNumber` 聚合；如果只需要模拟前端全校查询结果，直接使用平铺行。

### 全校课程查询样例

实测关键词：`大学英语`。

```http
POST /sys/xsxkapp/elective/queryCourse.do
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
token: <token>
```

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"campus\":\"<campus>\",\"electiveBatchCode\":\"<batchCode>\",\"isMajor\":\"1\",\"teachingClassType\":\"QXKC\",\"queryContent\":\"大学英语\"},\"pageSize\":\"10\",\"pageNumber\":\"0\",\"order\":\"\"}"
}
```

本次 `code=1`、`totalCount=663`、第一页 `dataList.length=10`。`QXKC` 返回的是教学班平铺行，不是课程汇总行；一门课的主课、实验/实践课序会作为多行出现。

第一页样例字段形态：

```json
{
  "teachingClassID": "202620271119103701",
  "courseNumber": "1191037",
  "courseName": "大学英语（Ⅰ）",
  "courseIndex": "01",
  "teacherName": "曹新萍(讲师)|<teacherCode>|",
  "departmentName": "语言文化学院",
  "courseNatureName": "必修",
  "courseTypeName": "公共必修课",
  "credit": "1.5",
  "hours": "32",
  "teachingPlace": "3-17周(单) 星期二 第3节-第4节 N8515",
  "schoolClassMap": {
    "<classCode>": "法学2601"
  },
  "limitKindList": [
    {
      "code": "01",
      "name": "班级",
      "limitValue": "<classCode>",
      "limitDesc": "法学2601"
    }
  ]
}
```

点击全校查询结果的“检查”会打开“能否选课原因分析”弹窗，并请求：

```http
GET /sys/xsxkapp/util/canchoose.do?xh=<studentCode>&jxbid=<teachingClassID>&xklcdm=<batchCode>&timestamp=<timestamp>
```

弹窗展示 `studentCode`、`teachingClassID`、轮次名、原因列表和教学班详情。实测 `大学英语（Ⅰ）/01` 返回原因包括“该轮次中没有找到教学班信息”，说明全校查询可以看到课程池里的教学班，但不等于当前轮次可选课对象。

### 方案内课程展开样例

实测关键词：`大学英语`。

```http
POST /sys/xsxkapp/elective/programCourse.do
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
token: <token>
```

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"campus\":\"<campus>\",\"electiveBatchCode\":\"<batchCode>\",\"isMajor\":\"1\",\"teachingClassType\":\"FANKC\",\"checkConflict\":\"2\",\"checkCapacity\":\"2\",\"queryContent\":\"大学英语\"},\"pageSize\":\"10\",\"pageNumber\":\"0\",\"order\":\"\"}"
}
```

本次 `code=1`、`totalCount=1`，返回课程汇总 `大学英语（Ⅲ）/2191069`，`number=30`，`selected=true`。前端点击课程条目后展开 `tcList`，不会额外请求列表接口。

课程汇总字段示例：

```json
{
  "courseNumber": "2191069",
  "courseName": "大学英语（Ⅲ）",
  "credit": "1.5",
  "courseNatureName": "必修",
  "departmentName": "语言文化学院",
  "number": 30,
  "selected": true,
  "tcList": []
}
```

教学班卡片由 `tcList[]` 渲染，卡片根节点 id 为 `<teachingClassID>_courseDiv`。卡片展示规则：

| 字段 | 展示/用途 |
| --- | --- |
| `courseIndex` + `engpName` + `teacherName` | 卡片标题，如 `[46-国际化教育-雅思英语]王丽萍` |
| `isChoose === "1"` | 显示“已选”和“退选” |
| `isConflict === "1"` | 显示“课程冲突”，`conflictDesc` 给出冲突明细 |
| `isFull === "1"` | 显示“人数已满”，容量文本为 `classCapacity 不可选` |
| `isFull === "0"` | 容量文本为 `numberOfSelected/classCapacity 可选` |
| `hasTest === "1"` | 显示“包含实验课” |
| `needOrderBook`, `needBook`, `hasBook` | 教材订购状态和“教材信息”入口 |
| `teachingPlace` | 上课周次、星期、节次、教室 |

本次 `大学英语（Ⅲ）` 的部分 `tcList` 形态：

```json
[
  {
    "teachingClassID": "202620271219106946",
    "courseIndex": "46",
    "engpName": "国际化教育-雅思英语",
    "teacherName": "王丽萍",
    "isChoose": "1",
    "isConflict": "0",
    "isFull": "1",
    "hasTest": "1",
    "numberOfSelected": "40",
    "classCapacity": "40",
    "needOrderBook": "1",
    "needBook": "0",
    "teachingPlace": "1-15周(单) 星期四 第3节-第4节 N9113"
  },
  {
    "teachingClassID": "202620271219106976",
    "courseIndex": "76",
    "engpName": "综-大学思辨英语视听说",
    "teacherName": "王少娟",
    "isChoose": null,
    "isConflict": "1",
    "isFull": "0",
    "hasTest": "1",
    "numberOfSelected": "29",
    "classCapacity": "30",
    "needOrderBook": "1",
    "needBook": null,
    "teachingPlace": "1-15周(单) 星期四 第3节-第4节 N8410"
  }
]
```

“教学班详情”弹窗直接使用 `tcList` 内存数据。本次详情弹窗展示三块：教师信息、推荐班级、教学班信息，没有发起额外 XHR。

## 已选与记录

| 用途 | 方法 | 路径 | 请求字段 | 本次响应 |
| --- | --- | --- | --- | --- |
| 已选课程 | GET | `/sys/xsxkapp/elective/courseResult.do` | `studentCode`, `electiveBatchCode`, `timestamp` | `code=1`, `totalCount=16`, `dataList` 为教学班行并附加选课结果字段 |
| 退选日志 | GET | `/sys/xsxkapp/elective/returnResults.do` | `studentCode`, `electiveBatchCode`, `timestamp` | `code=1`, 本次 `dataList` 为空 |
| 落选课程 | GET | `/sys/xsxkapp/elective/unsuccessful.do` | `isRead`, `studentCode`, `electiveBatchCode` | `code=1`, 本次 `dataList` 为空 |
| 队列信息 | GET | `/sys/xsxkapp/elective/queryStudentQueue.do` | `studentCode`, `electiveBatchCode` | `code=1`, 本次 `dataList` 为空 |
| 学分信息 | POST | `/sys/xsxkapp/student/xkxf.do` | `xh`, `xklcdm`, `xklclx` | `code=1`, `data` 为学生选课学分信息 |

`courseResult.do` 行额外字段：

```text
studentCode, isMajor, needOrderBook, trainingCode, deleteOperateTime,
teachingClassType, replaceCourseNumber, studentName, canDelete, selectStatus,
learnType, noOccupyCapacity, deleteOperateType, deleteOperateTypeName,
deleteOperatePersonName, operateIP, isConfirm, capacityType, comment
```

`xkxf.do` 的 `data` 字段：

```text
electiveIsOpen, levelTeaching, studentTag, getCreditProportion, collegeName,
departmentName, grade, schoolClass, schoolClassName, totalCredit, getCredit,
needCredit, campus, campusName, college, department, headImageUrl, gender,
trainingLevel, studentType, specialStudentType, majorTrainingCode,
minorTrainingCode, limitElective, majorName, majorDirection, majorDirectionName,
electiveBatch, lengthOfSchool, electiveBatchList, limitElectiveList,
noSelectReason, teachCampus, expElectiveBatchList, extendTrainingCode,
noSearchCj, spCourseDescription, major, code, name, wid
```

## 详情与校验

| 用途 | 方法 | 路径 | 请求字段 | 响应结构 |
| --- | --- | --- | --- | --- |
| 教学班详情 | GET | `/sys/xsxkapp/publicinfo/queryjxb.do` | `xklcdm`, `jxbid` | `code=1`, `data` 为教学班行字段 |
| 容量刷新 | GET | `/sys/xsxkapp/elective/teachingclass/capacity.do` | `teachingClassId`, `capacitySuffix`, `xh`, `timestamp` | `code=1`, `data` 为教学班行字段 |
| 可选校验 | GET | `/sys/xsxkapp/util/canchoose.do` | `xh`, `jxbid`, `xklcdm`, `timestamp` | `code=1`, `data.reasonList` 等 |
| 教材查询 | POST | `/sys/xsxkapp/textbook/queryxsjxbbook.do` | `xh`, `jxbid`, `xklcdm` | `code=1`, 本次 `dataList` 为空 |

`canchoose.do` 的 `data` 字段：

```text
studentCode, isMajor, electiveBatchCode, other, queryContent, checkCapacity,
courseNumber, campus, teachingClassType, checkConflict, orderBy, isdebug,
reasonList, wid
```

## 页面入口实测

| 页面 | 触发方式 | 业务接口 |
| --- | --- | --- |
| 主选课页 | 首页“开始选课” | `recommendedCourse.do`, `courseResult.do`, `guideMap.do`, `unsuccessful.do`, `publicinfo/fx/*`, `publicinfo/zx/*` |
| 顶部课程 tab | 逐个点击 `TJKC/FANKC/FAWKC/XGXK/CXKC/TYKC/FXKC/QXKC` | `recommendedCourse.do`, `programCourse.do`, `publicCourse.do`, `queryCourse.do` |
| 右侧已选课程 | 点击“已选课程” | `courseResult.do` |
| 已选课程弹窗退选日志 tab | 点击“退选日志” | `returnResults.do` |
| 右侧落选课程 | 点击“落选课程” | `unsuccessful.do?isRead=1` |
| 我的课表 | 点击“我的课表” | `teachingTime.do`, `noArranged.do` |
| 课程详情 | 点击课程列表“课程详情” | `querykcxx.do?kch=<courseNumber>` |

### 课表

```http
GET /sys/xsxkapp/elective/teachingTime.do?timestamp=<timestamp>&studentCode=<studentCode>&electiveBatchCode=<batchCode>
GET /sys/xsxkapp/elective/noArranged.do?timestamp=<timestamp>&studentCode=<studentCode>&electiveBatchCode=<batchCode>
```

### 课程详情

```http
GET /sys/xsxkapp/publicinfo/querykcxx.do?kch=<courseNumber>
```

### 教师详情

教师详情页面：

```http
GET /sys/xsxkapp/*default/jssimple.do?jsh=<teacherCode>
```

业务接口：

```http
GET /sys/xsxkapp/publicinfo/queryjzg.do?jsh=<teacherCode>
GET /sys/xsxkapp/publicinfo/queryjzgphoto.do?jsh=<teacherCode>
GET /sys/xsxkapp/publicinfo/celebrityfamous.do?timestamp=<timestamp>
```

`queryjzg.do` 本次 `code=1`，`data` 字段：

```text
NO, NAME, SEX, COUNTRY, JOB_TITLE, ADMINISTRATION_TITLE, FACULTY_NAME,
COMPANY_NAME, TUTOR_TYPE, TYPENAME, START_DATE, END_DATE,
UNDERGRADUATE_TOTAL_TEACH_TIME, GRADUATE_TOTAL_TEACH_TIME,
DESIGN_GUIDANCE_TOTAL_CNT, WORKS_TEXTBOOK_TOTAL_CNT,
EDU_REFORM_PROJECT_TOTAL_CNT, EDU_REFORM_PROJECT_CNT_GJJ,
EDU_REFORM_PROJECT_CNT_SBJ, TEACH_AWARDS_TOTAL_CNT,
TEACH_AWARDS_CNT_GJJ, TEACH_AWARDS_CNT_SBJ, TEACH_THESIS_TOTAL_CNT,
TEACH_THESIS_CNT_DYZZ, TEACH_THESIS_CNT_TXZZ,
EXCELLENT_COURSE_TOTAL_CNT, EXCELLENT_COURSE_CNT_GJJ,
EXCELLENT_COURSE_CNT_SBJ, TEACH_COMPETE_TOTAL_CNT,
TEACH_COMPETE_CNT_GJJ, TEACH_COMPETE_CNT_SBJ, TEACH_TEAMS_TOTAL_CNT,
TEACH_TEAMS_CNT_GJJ, TEACH_TEAMS_CNT_SBJ, PERIODICAL_THESIS_TOTAL_CNT,
SCIENTIFIC_AWARDS_TOTAL_CNT, ACADEMIC_MASTERWORK_TOTAL_CNT,
ACADEMIC_CONFERENCE_TOTAL_CNT, CONFERENCE_THESIS_TOTAL_CNT,
SERVICE_WORK_TOTAL_CNT, SOCIETY_HONOR_TOTAL_CNT, wid
```

### 成绩详情

成绩详情页面：

```http
GET /sys/xsxkapp/*default/scoredetail.do
```

前端读取 `sessionStorage.studentInfo` 后请求：

```http
POST /sys/xsxkapp/student/xscj.do
token: <token>
Content-Type: application/x-www-form-urlencoded; charset=UTF-8

electiveBatchCode=<batchCode>&studentCode=<studentCode>
```

本次在主选课页登录态下只读调用，响应为：

```json
{
  "code": "0",
  "msg": "不能查看成绩:成绩菜单未开放"
}
```

源码显示开放时按 `schoolTermName` 分组，表格使用字段：

```text
schoolTermName, courseNumber, courseName, credit, score, retakeTypeName
```

### 公告与常见问题

公告列表页：

```http
GET /sys/xsxkapp/*default/publicinfo.do?type=notice
GET /sys/xsxkapp/publicinfo/notice.do?timestamp=<timestamp>&pageSize=10&pageNumber=0
```

公告列表行字段：

```text
title, publishTime, timeDescription, filename, content, wid
```

公告详情页：

```http
GET /sys/xsxkapp/*default/content.do?id=<wid>
GET /sys/xsxkapp/publicinfo/notice/view.do?timestamp=<timestamp>&wid=<wid>
```

详情响应 `data` 字段同公告列表行；页面显示 `title`、`timeDescription`、`content`，有 `filename` 时显示下载入口。

常见问题页：

```http
GET /sys/xsxkapp/*default/publicinfo.do?type=problem
GET /sys/xsxkapp/publicinfo/problem.do?timestamp=<timestamp>
```

问题列表行字段：

```text
title, publishTime, timeDescription, content, serialNumber, wid
```

## 初始化与字典补充

### 轮次开放状态

```http
POST /sys/xsxkapp/elective/batchisopen.do
token: <token>
Content-Type: application/x-www-form-urlencoded; charset=UTF-8

xklcdm=<batchCode>
```

本次返回 `code=1`、`msg=1`。该接口用于确认当前选课轮次开放状态。

### 首页聚合

```http
GET /sys/xsxkapp/publicinfo.do?timestamp=<timestamp>&pageSize=10&pageNumber=1
```

本次返回 `code=1`，`data` 包含：

```text
celebrityFamousList, consultMethod, noticeList, commonProblemList, stopInfo, wid
```

### 筛选字典

```http
GET /sys/xsxkapp/publicinfo/volunteer.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/fx/nj.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/fx/yx.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/fx/zy.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/zx/nj.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/zx/yx.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/zx/zy.do?timestamp=<timestamp>
```

`volunteer.do` 本次返回 `code=1`，`dataList.length=5`，行字段：

```text
grade, isUse, name, wid
```

`fx/*` 和 `zx/*` 本次均返回 `code=1`。`zx/zy.do` 的 `msg` 是一段较大的 JSON 字符串字典；文档只保留字段形态，不保存原始完整值。

### 引导页读取状态

```http
GET /sys/xsxkapp/student/guideMap.do?timestamp=<timestamp>&studentCode=<studentCode>
```

本次返回 `code=1`、`msg=已读引导页`。未调用 POST 标记已读接口。

## 课程辅助查询补充

### 课程所属方案

```http
POST /sys/xsxkapp/elective/course/kcssfa.do
token: <token>
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"electiveBatchCode\":\"<batchCode>\",\"courseNumber\":\"<courseNumber>\"},\"pageSize\":\"10\",\"pageNumber\":\"0\"}"
}
```

本次返回 `code=1`、`totalCount=83`、第一页 `dataList.length=10`。实际行字段比静态展示字段更多，形态接近课程汇总行：

```text
credit, courseUrl, majorFlag, courseFlag, replaceCourseName, courseNumber,
courseName, courseNatureName, retakeType, retakeTypeDetail, departmentName,
campusName, replaceCourseNumber, number, selected, tcList, type, typeName,
hours, wid
```

### 实验课查询

```http
POST /sys/xsxkapp/elective/testCourse.do
```

本次用 `大学英语` 相关查询条件返回 `code=1`、`msg=查询实验课程成功`、`dataList.length=1`。响应 `map` 中包含两个教学班/教材相关的键；不保存原始键值。

### 静态分支复测

以下接口在静态源码中存在；本次继续从运行期补测后，`course.do` 和 `course/volunteer.do` 的有效参数已经确认，`volunteered.do` 仍表现为当前部署不可用：

| 接口 | 本次结果 |
| --- | --- |
| `GET /sys/xsxkapp/elective/course.do` | 返回 HTML 页面；静态封装的 GET 形态不是业务 JSON |
| `POST /sys/xsxkapp/elective/course.do` | `code=1`，返回课程汇总行；`TJKC=11`、`FANKC=15`、`TYKC=1` |
| `GET /sys/xsxkapp/elective/course/volunteer.do` | `queryParam={"data":...}` 时 `code=1`，返回可选志愿等级 |
| `GET /sys/xsxkapp/elective/volunteered.do` | 返回 404 HTML；`selectedvolunteer.do` 片段实际通过 `courseResult.do` 取已选数据 |

`course.do` 的有效请求体：

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"campus\":\"<campus>\",\"electiveBatchCode\":\"<batchCode>\",\"isMajor\":\"1\",\"teachingClassType\":\"FANKC\",\"checkConflict\":\"2\",\"checkCapacity\":\"2\",\"queryContent\":\"\"},\"pageSize\":\"100\",\"pageNumber\":\"0\",\"order\":\"\"}"
}
```

`course.do` 对各类型的本次实测：

| 类型 | code | totalCount | 备注 |
| --- | ---: | ---: | --- |
| `TJKC` | `1` | 11 | 课程汇总行，含 `tcList` |
| `FANKC` | `1` | 15 | 课程汇总行，含 `tcList` |
| `FAWKC` | `0` | - | 方案外课程未开放 |
| `XGXK` | `0` | - | 通识类选修课选课未开放 |
| `CXKC` | `0` | - | 重修课程报名未开放 |
| `TYKC` | `1` | 1 | 课程汇总行，含 `tcList` |
| `FXKC` | `0` | - | 辅修未开放 |
| `QXKC` | `1` | 0 | 该入口不承担全校课程平铺查询 |

`course/volunteer.do` 的有效参数：

```json
{
  "queryParam": "{\"data\":{\"studentCode\":\"<studentCode>\",\"electiveBatchCode\":\"<batchCode>\",\"courseNumber\":\"<courseNumber>\"}}"
}
```

本次返回 `code=1`、`msg=查询学生选课时，选择课程可选的志愿等级成功`、`dataList.length=1`，行字段：

```text
grade, isUse, name, wid
```

同时补充保存了志愿弹窗片段快照：

```text
artifacts/latest/snapshot/selectedvolunteer.html
```

该片段只包含必修志愿列表、公选志愿列表和实验课行模板，不包含额外脚本引用。`sidebar.js` 加载该片段后调用 `selectedcourse.js` 的 `initSelectCourse()` / `CVCourseResult.init()`，数据来源仍是 `courseResult.do`。

## 轮次观测快照

2026-07-01 补测时，在当前登录态下重新请求学生信息与选课批次接口。本节只保存当时响应里的一个样本，用来解释后续补测时课程池和 2026-06-30 正选样例不同；客户端实现不得把这里的数量、名称或日期写成默认轮次。

当时接口返回的开放普通轮次样本为：

```text
2026秋季学期网上选课（形势与政策、开设多学期同一课号课程）
```

摘要：

```text
batchType=01, canSelect=1, tacticCode=01,
beginTime=2026-06-29 15:00:00, endTime=2026-07-03 18:00:00
```

这只是“当前账号、当前时间点、当前登录态”的接口观测；系统一年内会有多个轮次，实际可见范围必须以登录后接口返回为准。此前已记录的 `大学英语（Ⅲ）`、全校课程大页、方案内完整列表等样例仍以 2026-06-30 的快照和运行期摘要为准。
