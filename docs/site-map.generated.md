# BKSXK 静态站点地图

生成时间：2026-07-01T03:16:52.636Z

扫描来源：`static/content.js`, `static/departurelog.js`, `static/departurelogBS.js`, `static/grablessons.js`, `static/grablessonsBS.js`, `static/index.min.js`, `static/indexBS.min.js`, `static/jssimple.js`, `static/jssimpleBs.js`, `static/loginInUserRegister.js`, `static/publicinfo.js`, `static/publicinfoBS.js`, `static/scoredetail.js`, `static/scoredetailBs.js`, `static/selectedcourse.js`, `static/selectedcourseBS.js`, `static/sidebar.js`, `static/xsxkpub.js`

统计：页面/片段 17 个，API 56 个，写操作相关接口 12 个，函数/模块标识 327 个。

> 本文档来自静态脚本快照的自动提取，会解析 `BH_UTILS.doAjax`、`BH_UTILS.doSyncAjax`、`$.get`、`$.post` 和 `$.ajax({ url, type })`。动态条件分支仍需要通过受保护浏览器逐项验证。

## 页面与片段入口

| 入口 | 方法 | 来源 | 附近函数 |
| --- | --- | --- | --- |
| `./departurelog.do` | - | `static/sidebar.js:466` | `initTabContent` |
| `./selectedcourse.do` | - | `static/sidebar.js:473` | `initTabContent` |
| `./selectedvolunteer.do` | - | `static/sidebar.js:452` | `initTabContent` |
| `/sys/xsxkapp/*default/content.do?id=` | - | `static/index.min.js:1` | `t` |
| `/sys/xsxkapp/*default/coursedetail.do?courseNum=` | - | `static/grablessons.js:573` | `-` |
| `/sys/xsxkapp/*default/curriculavariable.do?token=` | - | `static/index.min.js:1` | `t` |
| `/sys/xsxkapp/*default/curriculum.do` | - | `static/sidebar.js:113` | `-` |
| `/sys/xsxkapp/*default/departurelog.do` | - | `static/grablessons.js:4870` | `departureLogClickBinding` |
| `/sys/xsxkapp/*default/expcurriculavariable.do?token=` | - | `static/index.min.js:1` | `t` |
| `/sys/xsxkapp/*default/expcurriculum.do` | - | `static/sidebar.js:111` | `-` |
| `/sys/xsxkapp/*default/grablessons.do?token=` | - | `static/index.min.js:1` | `t` |
| `/sys/xsxkapp/*default/index.do` | - | `static/departurelog.js:66` | `initTable` |
| `/sys/xsxkapp/*default/jcdetail.do?jxbid=` | - | `static/grablessons.js:1051` | `-` |
| `/sys/xsxkapp/*default/jssimple.do?jsh=` | - | `static/grablessons.js:3736` | `-` |
| `/sys/xsxkapp/*default/jssimple1.do?jsh=` | - | `static/grablessons.js:3738` | `-` |
| `/sys/xsxkapp/*default/publicinfo.do?type=` | - | `static/index.min.js:1` | `i` |
| `/sys/xsxkapp/*default/scoredetail.do` | - | `static/sidebar.js:188` | `-` |

## API 入口

| 接口 | 方法 | 分类 | 来源 | 附近函数 |
| --- | --- | --- | --- | --- |
| `/sys/xsxkapp/elective/submit/unsuccessful.do?wids=` | - | 写操作 | `static/xsxkpub.js:175` | `submitUnSuccessful` |
| `/sys/xsxkapp/elective/teachingclass/capacity.do?teachingClassId=` | - | 静态引用 | `static/grablessonsBS.js:10` | `queryTeachingClassCapacity` |
| `/sys/xsxkapp/elective/unsuccessful.do?isRead=` | - | 静态引用 | `static/xsxkpub.js:165` | `queryUnSuccessful` |
| `/sys/xsxkapp/publicinfo/queryjxb.do?xklcdm=` | - | 静态引用 | `static/xsxkpub.js:201` | `queryJxbInfo` |
| `/sys/xsxkapp/publicinfo/queryjzgphoto.do?jsh=` | - | 静态引用 | `static/jssimple.js:186` | `-` |
| `/sys/xsxkapp/student/guideMap.do?timestamp=` | - | 静态引用 | `static/grablessons.js:4974` | `queryIsReadGuideMap` |
| `/sys/xsxkapp/student/vcode/image.do?vtoken=` | - | 静态引用 | `static/index.min.js:1` | `i` |
| `/sys/xsxkapp/util/canchoose.do` | - | 静态引用 | `static/xsxkpub.js:257` | `querySfCanChoose` |
| `/sys/xsxkapp/elective/batch.do?timestamp={e}` | GET | GET 查询 | `static/indexBS.min.js:1` | `queryTestBatch` |
| `/sys/xsxkapp/elective/course.do?timestamp={timestamp}` | GET | GET 查询 | `static/xsxkpub.js:91` | `queryCourse` |
| `/sys/xsxkapp/elective/course/volunteer.do?timestamp={timestamp}` | GET | GET 查询 | `static/xsxkpub.js:154` | `queryCourseCanSelectVolunteer` |
| `/sys/xsxkapp/elective/courseResult.do?timestamp={timestamp}` | GET | GET 查询 | `static/selectedcourseBS.js:6` | `queryChooseCourse` |
| `/sys/xsxkapp/elective/deleteVolunteer.do?timestamp={timestamp}` | GET | 写操作 | `static/selectedcourseBS.js:20` | `deleteVolunteerResult` |
| `/sys/xsxkapp/elective/queryStudentQueue.do` | GET | GET 查询 | `static/xsxkpub.js:340` | `queryStudentQueue` |
| `/sys/xsxkapp/elective/returnResults.do?timestamp={timestamp}` | GET | GET 查询 | `static/departurelogBS.js:3` | `queryStudentReturnResults` |
| `/sys/xsxkapp/elective/submit/unsuccessful.do?wids={wids}&studentCode={xh}` | GET | 写操作 | `static/xsxkpub.js:174` | `submitUnSuccessful` |
| `/sys/xsxkapp/elective/teachingclass/capacity.do?teachingClassId={teachingClassId}&capacitySuffix={capacitySuffix}&xh={xh}&timestamp={timestamp}` | GET | GET 查询 | `static/grablessonsBS.js:9` | `queryTeachingClassCapacity` |
| `/sys/xsxkapp/elective/unsuccessful.do?isRead={isRead}&studentCode={xh}&electiveBatchCode={xklcdm}` | GET | GET 查询 | `static/xsxkpub.js:164` | `queryUnSuccessful` |
| `/sys/xsxkapp/elective/volunteered.do?timestamp={t}` | GET | GET 查询 | `static/indexBS.min.js:1` | `queryVolunteered` |
| `/sys/xsxkapp/publicinfo.do?timestamp={t}` | GET | GET 查询 | `static/indexBS.min.js:1` | `queryPublicInfo` |
| `/sys/xsxkapp/publicinfo/celebrityfamous.do?timestamp={timestamp}` | GET | GET 查询 | `static/content.js:60` | `queryCelebrityFamous` |
| `/sys/xsxkapp/publicinfo/dictionary.do?timestamp={e}` | GET | GET 查询 | `static/indexBS.min.js:1` | `queryDictionary` |
| `/sys/xsxkapp/publicinfo/fx/{type}.do?timestamp={timestamp}` | GET | GET 查询 | `static/xsxkpub.js:234` | `queryYxNjZyData` |
| `/sys/xsxkapp/publicinfo/notice.do?timestamp={timestamp}` | GET | GET 查询 | `static/publicinfoBS.js:3` | `queryNoticeList` |
| `/sys/xsxkapp/publicinfo/notice/view.do?timestamp={timestamp}` | GET | GET 查询 | `static/content.js:51` | `queryNoticeView` |
| `/sys/xsxkapp/publicinfo/onlineUsers.do?timestamp={e}` | GET | GET 查询 | `static/indexBS.min.js:1` | `queryOnlineUsers` |
| `/sys/xsxkapp/publicinfo/problem.do?timestamp={timestamp}` | GET | GET 查询 | `static/publicinfoBS.js:13` | `queryProblemList` |
| `/sys/xsxkapp/publicinfo/queryjxb.do?xklcdm={xklcdm}&jxbid={jxbid}` | GET | GET 查询 | `static/xsxkpub.js:200` | `queryJxbInfo` |
| `/sys/xsxkapp/publicinfo/queryjzg.do?jsh={JSH}` | GET | GET 查询 | `static/jssimpleBs.js:6` | `queryJsInfo` |
| `/sys/xsxkapp/publicinfo/sysparam.do?timestamp={e}` | GET | GET 查询 | `static/indexBS.min.js:1` | `querySysParam` |
| `/sys/xsxkapp/publicinfo/volunteer.do?timestamp={timestamp}` | GET | GET 查询 | `static/xsxkpub.js:130` | `queryVolunteerData` |
| `/sys/xsxkapp/publicinfo/zx/{type}.do?timestamp={timestamp}` | GET | GET 查询 | `static/xsxkpub.js:245` | `querySkYxNjZyData` |
| `/sys/xsxkapp/student/<studentCode>.do?timestamp={t}` | GET | GET 查询 | `static/index.min.js:1` | `i` |
| `/sys/xsxkapp/student/4/vcode.do?timestamp={e}` | GET | GET 查询 | `static/indexBS.min.js:1` | `queryVocdeToken` |
| `/sys/xsxkapp/student/authlogout.do?timestamp={t}` | GET | 写操作 | `static/indexBS.min.js:1` | `autoLogOut` |
| `/sys/xsxkapp/student/check/login.do?timestrap={d}` | GET | GET 查询 | `static/index.min.js:1` | `t` |
| `/sys/xsxkapp/student/guideMap.do?timestamp={timestamp}&studentCode={studentCode}` | GET | GET 查询 | `static/grablessons.js:4973` | `queryIsReadGuideMap` |
| `/sys/xsxkapp/student/logout.do?timestamp={t}` | GET | 写操作 | `static/indexBS.min.js:1` | `studentLogOut` |
| `/sys/xsxkapp/student/register.do?number={e}` | GET | 写操作 | `static/indexBS.min.js:1` | `loginInUserRegister` |
| `/sys/xsxkapp/util/canchoose.do?xh={xh}&jxbid={jxbid}&xklcdm={xklcdm}&timestamp={timestamp}` | GET | GET 查询 | `static/xsxkpub.js:256` | `querySfCanChoose` |
| `/sys/xsxkapp/elective/batchisopen.do` | POST | POST 查询 | `static/indexBS.min.js:1` | `queryXklcSfkf` |
| `/sys/xsxkapp/elective/course/kcssfa.do` | POST | POST 查询 | `static/xsxkpub.js:267` | `queryFaDetail` |
| `/sys/xsxkapp/elective/programCourse.do` | POST | POST 查询 | `static/xsxkpub.js:116` | `queryProgramCourse` |
| `/sys/xsxkapp/elective/publicCourse.do` | POST | POST 查询 | `static/xsxkpub.js:103` | `queryPublicCourse` |
| `/sys/xsxkapp/elective/queryCourse.do` | POST | POST 查询 | `static/xsxkpub.js:223` | `queryCourseData` |
| `/sys/xsxkapp/elective/recommendedCourse.do` | POST | POST 查询 | `static/xsxkpub.js:78` | `queryRecommendedCourse` |
| `/sys/xsxkapp/elective/studentstatus.do` | POST | 写操作状态 | `static/xsxkpub.js:443` | `queryOperateProcess` |
| `/sys/xsxkapp/elective/testCourse.do` | POST | POST 查询 | `static/xsxkpub.js:213` | `queryTestCourse` |
| `/sys/xsxkapp/elective/volunteer.do` | POST | 写操作 | `static/xsxkpub.js:143` | `addVolunteer` |
| `/sys/xsxkapp/student/guideMap.do?studentCode={studentCode}` | POST | 写操作 | `static/grablessons.js:4938` | `setReadGuideMap` |
| `/sys/xsxkapp/student/xklcqr.do` | POST | 写操作 | `static/xsxkpub.js:277` | `makeSureLcxz` |
| `/sys/xsxkapp/student/xkxf.do` | POST | POST 查询 | `static/indexBS.min.js:1` | `queryXkxf` |
| `/sys/xsxkapp/student/xscj.do` | POST | POST 查询 | `static/scoredetailBs.js:5` | `queryXkScore` |
| `/sys/xsxkapp/textbook/addbook.do` | POST | 写操作 | `static/selectedcourseBS.js:33` | `bookJxbJcResult` |
| `/sys/xsxkapp/textbook/modifybook.do` | POST | 写操作 | `static/selectedcourseBS.js:45` | `delBookJxbJcResult` |
| `/sys/xsxkapp/textbook/queryxsjxbbook.do` | POST | POST 查询 | `static/selectedcourseBS.js:70` | `queryJxbJcResult` |

## 写操作接口

| 接口 | 方法 | 来源 | 附近函数 |
| --- | --- | --- | --- |
| `/sys/xsxkapp/elective/submit/unsuccessful.do?wids=` | - | `static/xsxkpub.js:175` | `submitUnSuccessful` |
| `/sys/xsxkapp/elective/deleteVolunteer.do?timestamp={timestamp}` | GET | `static/selectedcourseBS.js:20` | `deleteVolunteerResult` |
| `/sys/xsxkapp/elective/submit/unsuccessful.do?wids={wids}&studentCode={xh}` | GET | `static/xsxkpub.js:174` | `submitUnSuccessful` |
| `/sys/xsxkapp/student/authlogout.do?timestamp={t}` | GET | `static/indexBS.min.js:1` | `autoLogOut` |
| `/sys/xsxkapp/student/logout.do?timestamp={t}` | GET | `static/indexBS.min.js:1` | `studentLogOut` |
| `/sys/xsxkapp/student/register.do?number={e}` | GET | `static/indexBS.min.js:1` | `loginInUserRegister` |
| `/sys/xsxkapp/elective/studentstatus.do` | POST | `static/xsxkpub.js:443` | `queryOperateProcess` |
| `/sys/xsxkapp/elective/volunteer.do` | POST | `static/xsxkpub.js:143` | `addVolunteer` |
| `/sys/xsxkapp/student/guideMap.do?studentCode={studentCode}` | POST | `static/grablessons.js:4938` | `setReadGuideMap` |
| `/sys/xsxkapp/student/xklcqr.do` | POST | `static/xsxkpub.js:277` | `makeSureLcxz` |
| `/sys/xsxkapp/textbook/addbook.do` | POST | `static/selectedcourseBS.js:33` | `bookJxbJcResult` |
| `/sys/xsxkapp/textbook/modifybook.do` | POST | `static/selectedcourseBS.js:45` | `delBookJxbJcResult` |

## 函数与模块索引

| 函数/模块 | 来源 |
| --- | --- |
| `a` | `static/index.min.js:1` |
| `a` | `static/index.min.js:1` |
| `addVolunteer` | `static/xsxkpub.js:142` |
| `autoLogOut` | `static/indexBS.min.js:1` |
| `autoLogOut` | `static/xsxkpub.js:183` |
| `bindChangeCampus` | `static/grablessons.js:5259` |
| `bindGoHome` | `static/grablessons.js:5253` |
| `bindLogOutClick` | `static/grablessons.js:5239` |
| `bindOpenView` | `static/publicinfo.js:91` |
| `bindPaging` | `static/publicinfo.js:79` |
| `bindPublicScrollPage` | `static/xsxkpub.js:307` |
| `bindSfSearch` | `static/grablessons.js:5664` |
| `bindXklxSearch` | `static/grablessons.js:5673` |
| `bookJxbJc` | `static/selectedcourse.js:748` |
| `bookJxbJcResult` | `static/selectedcourseBS.js:32` |
| `btnHandle` | `static/grablessons.js:2448` |
| `btnHandle` | `static/grablessons.js:4024` |
| `btnHandle` | `static/selectedcourse.js:708` |
| `buildAddVolunteerParam` | `static/grablessons.js:4477` |
| `buildCourseListHtml` | `static/grablessons.js:1454` |
| `buildCourseResultList` | `static/selectedcourse.js:112` |
| `buildNoticeList` | `static/publicinfo.js:53` |
| `buildProblemList` | `static/publicinfo.js:120` |
| `buildPublicCourseListHtml` | `static/grablessons.js:1592` |
| `buildQueryTCParam` | `static/grablessons.js:4262` |
| `buildSchoolCourseListHtml` | `static/grablessons.js:1816` |
| `buildTableHtml` | `static/departurelog.js:73` |
| `buildUnsuccessfulTable` | `static/sidebar.js:395` |
| `c` | `static/index.min.js:1` |
| `c` | `static/index.min.js:1` |
| `c` | `static/index.min.js:1` |
| `cancelHandle` | `static/grablessons.js:2460` |
| `cancelHandle` | `static/grablessons.js:4038` |
| `cancelHandle` | `static/selectedcourse.js:722` |
| `changeCopyRight` | `static/xsxkpub.js:5` |
| `changeJcWdgyy` | `static/grablessons.js:5749` |
| `changeJcWdgyy` | `static/selectedcourse.js:873` |
| `changeTskName` | `static/xsxkpub.js:295` |
| `checkIsConflict` | `static/xsxkpub.js:452` |
| `checkNull` | `static/grablessons.js:3755` |
| `checkSfkxqSelect` | `static/grablessons.js:617` |
| `choiceTestCourse` | `static/grablessons.js:3017` |
| `clearProcessInterval` | `static/xsxkpub.js:431` |
| `closeAside` | `static/grablessons.js:146` |
| `contentChange` | `static/grablessons.js:155` |
| `dealEmptyData` | `static/xsxkpub.js:383` |
| `dealTeachingPlace` | `static/xsxkpub.js:359` |
| `dealWithStudentInfo` | `static/sidebar.js:354` |
| `delBookJxbJcResult` | `static/selectedcourseBS.js:44` |
| `deleteCourseResult` | `static/selectedcourse.js:442` |
| `deleteVolunteer` | `static/grablessons.js:2515` |
| `deleteVolunteer` | `static/selectedcourse.js:810` |
| `deleteVolunteerResult` | `static/selectedcourseBS.js:18` |
| `departureLogClickBinding` | `static/grablessons.js:4868` |
| `eventsListen` | `static/grablessons.js:118` |
| `eventsListen` | `static/grablessons.js:503` |
| `eventsListen` | `static/grablessons.js:2741` |
| `eventsListen` | `static/grablessons.js:3997` |
| `expertModeSorting` | `static/grablessons.js:4195` |
| `falistReload` | `static/grablessons.js:1956` |
| `flushTeachingClassCapacity` | `static/grablessons.js:5096` |
| `getColHtml` | `static/grablessons.js:2113` |
| `getDesKeys` | `static/indexBS.min.js:1` |
| `getHtml` | `static/grablessons.js:195` |
| `getItemPositionStyle` | `static/grablessons.js:4009` |
| `getJcHtml` | `static/grablessons.js:2841` |
| `getRowHtml` | `static/grablessons.js:2098` |
| `getSelectJcxx` | `static/grablessons.js:2826` |
| `getUuid` | `static/xsxkpub.js:371` |
| `hidePublicFoot` | `static/xsxkpub.js:303` |
| `hidePublicJxbxq` | `static/xsxkpub.js:299` |
| `hideStep` | `static/grablessons.js:4964` |
| `jxbInfoWindow` | `static/grablessons.js:748` |
| `l` | `static/index.min.js:1` |
| `listInit` | `static/grablessons.js:3088` |
| `listInit` | `static/grablessons.js:3181` |
| `listInit` | `static/grablessons.js:3270` |
| `listInit` | `static/grablessons.js:3358` |
| `listInit` | `static/grablessons.js:3446` |
| `listInit` | `static/grablessons.js:3536` |
| `listInit` | `static/grablessons.js:3785` |
| `listInit` | `static/grablessons.js:3872` |
| `listReload` | `static/grablessons.js:3127` |
| `listReload` | `static/grablessons.js:3207` |
| `listReload` | `static/grablessons.js:3296` |
| `listReload` | `static/grablessons.js:3384` |
| `listReload` | `static/grablessons.js:3472` |
| `listReload` | `static/grablessons.js:3569` |
| `listReload` | `static/grablessons.js:3811` |
| `listReload` | `static/grablessons.js:3898` |
| `loginInUserRegister` | `static/indexBS.min.js:1` |
| `loginInUserRegister` | `static/xsxkpub.js:350` |
| `logOut` | `static/grablessons.js:2571` |
| `makeSureLcxz` | `static/xsxkpub.js:276` |
| `minorInit` | `static/grablessons.js:1191` |
| `minorReload` | `static/grablessons.js:1224` |
| `o` | `static/index.min.js:1` |
| `o` | `static/index.min.js:1` |
| `openAside` | `static/grablessons.js:138` |
| `openCourseTeacherList` | `static/grablessons.js:840` |
| `openCourseViewWindow` | `static/grablessons.js:3600` |
| `openElectiveBatchWindow` | `static/sidebar.js:198` |
| `openRows` | `static/grablessons.js:3238` |
| `openRows` | `static/grablessons.js:3327` |
| `openRows` | `static/grablessons.js:3415` |
| `openRows` | `static/grablessons.js:3503` |
| `openRows` | `static/grablessons.js:3842` |
| `openRows` | `static/grablessons.js:3928` |
| `openTestCourseWindow` | `static/grablessons.js:2873` |
| `pageFaList` | `static/grablessons.js:1943` |
| `pageHeadTabChange` | `static/grablessons.js:2755` |
| `pagingCourse` | `static/grablessons.js:4749` |
| `Plugin` | `static/grablessons.js:4123` |
| `programInit` | `static/grablessons.js:1348` |
| `programReload` | `static/grablessons.js:1382` |
| `publicInit` | `static/grablessons.js:1537` |
| `publicReloda` | `static/grablessons.js:1573` |
| `queryCelebrityFamous` | `static/content.js:58` |
| `queryCelebrityFamous` | `static/jssimpleBs.js:13` |
| `queryCelebrityFamous` | `static/selectedcourseBS.js:57` |
| `queryCelebrityFamous` | `static/xsxkpub.js:17` |
| `queryChooseCourse` | `static/selectedcourseBS.js:4` |
| `queryCourse` | `static/xsxkpub.js:89` |
| `queryCourseCanSelectVolunteer` | `static/xsxkpub.js:152` |
| `queryCourseData` | `static/xsxkpub.js:222` |
| `queryDictionary` | `static/indexBS.min.js:1` |
| `queryError` | `static/selectedcourse.js:426` |
| `queryFaDetail` | `static/xsxkpub.js:266` |
| `queryIsReadGuideMap` | `static/grablessons.js:4969` |
| `queryJsInfo` | `static/jssimpleBs.js:4` |
| `queryJxbInfo` | `static/xsxkpub.js:199` |
| `queryJxbJcResult` | `static/selectedcourseBS.js:69` |
| `queryNoticeList` | `static/publicinfoBS.js:1` |
| `queryNoticeView` | `static/content.js:49` |
| `queryOnlineUsers` | `static/indexBS.min.js:1` |
| `queryOperateProcess` | `static/xsxkpub.js:441` |
| `queryProblemList` | `static/publicinfoBS.js:11` |
| `queryProgramCourse` | `static/xsxkpub.js:115` |
| `queryPublicCourse` | `static/xsxkpub.js:102` |
| `queryPublicInfo` | `static/indexBS.min.js:1` |
| `queryRecommendedCourse` | `static/xsxkpub.js:77` |
| `querySelectCourseNum` | `static/grablessons.js:5069` |
| `querySfCanChoose` | `static/xsxkpub.js:254` |
| `querySkYxNjZyData` | `static/xsxkpub.js:243` |
| `queryStudentInformation` | `static/indexBS.min.js:1` |
| `queryStudentQueue` | `static/xsxkpub.js:339` |
| `queryStudentReturnResults` | `static/departurelogBS.js:1` |
| `querySysParam` | `static/indexBS.min.js:1` |
| `queryTeachingClassCapacity` | `static/grablessonsBS.js:4` |
| `queryTestBatch` | `static/indexBS.min.js:1` |
| `queryTestCourse` | `static/xsxkpub.js:212` |
| `queryUnSuccessful` | `static/xsxkpub.js:163` |
| `queryVocdeToken` | `static/indexBS.min.js:1` |
| `queryVolunteerData` | `static/xsxkpub.js:128` |
| `queryVolunteered` | `static/indexBS.min.js:1` |
| `queryXklcSfkf` | `static/indexBS.min.js:1` |
| `queryXklcSfkfBySync` | `static/indexBS.min.js:1` |
| `queryXkScore` | `static/scoredetailBs.js:4` |
| `queryXkxf` | `static/indexBS.min.js:1` |
| `queryXkxf` | `static/xsxkpub.js:328` |
| `queryYxNjZyData` | `static/xsxkpub.js:232` |
| `randomNumBoth` | `static/content.js:107` |
| `randomNumBoth` | `static/publicinfo.js:179` |
| `randomNumBoth` | `static/selectedcourse.js:72` |
| `randomNumBoth` | `static/xsxkpub.js:62` |
| `RandomNumBoth` | `static/content.js:42` |
| `recommendInit` | `static/grablessons.js:1138` |
| `recommendReload` | `static/grablessons.js:1172` |
| `reloadCourseList` | `static/grablessons.js:5183` |
| `reloadTable` | `static/grablessons.js:4828` |
| `remindUnSuccessfulCourse` | `static/grablessons.js:4987` |
| `removeDialog` | `static/grablessons.js:2603` |
| `removeDialog` | `static/grablessons.js:2639` |
| `removeDialog` | `static/grablessons.js:4085` |
| `removeDialog` | `static/selectedcourse.js:744` |
| `resetTableHeight` | `static/grablessons.js:2051` |
| `restoreScroll` | `static/grablessons.js:2596` |
| `retakeInit` | `static/grablessons.js:1242` |
| `retakeReload` | `static/grablessons.js:1276` |
| `s` | `static/index.min.js:1` |

