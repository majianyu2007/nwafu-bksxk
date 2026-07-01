# BKSXK API 研究笔记

本笔记来自两类证据：

- 运行期日志：`artifacts/latest/network.jsonl`，已用 `npm run sanitize` 清洗敏感值。
- 前端静态脚本：`static-snapshot/bksxk.nwafu.edu.cn/xsxkapp/static/` 下的 `xsxkpub.js`、`grablessons.js`、`selectedcourseBS.js`、`index.min.js` 等。
- 公共静态资源：`static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/` 下的页面 JS/CSS/图片。

`artifacts/` 不提交。里面可能包含截图、页面 DOM、课程信息、登录后接口响应。

可提交静态资源清单见 `docs/static-assets.manifest.generated.json`，当前固定 79 个文件的大小和 SHA-256。

## 基础约定

- 业务前缀：`https://bksxk.nwafu.edu.cn/xsxkapp`
- 页面静态资源主要来自：`https://xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/`
- 多数登录后接口由前端加请求头：`token: sessionStorage.token`
- 主要上下文来自 `sessionStorage`：
  - `token`
  - `studentInfo`
  - `currentBatch`
  - `currentCampus`
  - `teachingClassType`
  - `electiveIsOpen`

## 登录与初始化

| 用途 | 方法 | 路径 | 主要参数 |
| --- | --- | --- | --- |
| 登录态可见轮次 | GET | `/sys/xsxkapp/elective/batch.do` | `timestamp` |
| 轮次是否开放 | POST | `/sys/xsxkapp/elective/batchisopen.do` | `xklcdm` |
| 验证码 token | GET | `/sys/xsxkapp/student/4/vcode.do` | `timestamp` |
| 验证码图片 | GET | `/sys/xsxkapp/student/vcode/image.do` | `vtoken` |
| 登录校验 | GET | `/sys/xsxkapp/student/check/login.do` | `timestrap`, `loginName`, `loginPwd`, `verifyCode`, `vtoken` |
| 学生信息 | GET | `/sys/xsxkapp/student/<studentCode>.do` | `timestamp` |
| 选课轮次须知确认 | POST | `/sys/xsxkapp/student/xklcqr.do` | `electiveBatchCode`, `studentCode` |
| 字典 | GET | `/sys/xsxkapp/publicinfo/dictionary.do` | `timestamp` |
| 系统参数 | GET | `/sys/xsxkapp/publicinfo/sysparam.do` | `timestamp`, `_` |
| 首页聚合信息 | GET | `/sys/xsxkapp/publicinfo.do` | `timestamp`, `pageSize`, `pageNumber` |
| 在线人数 | GET | `/sys/xsxkapp/publicinfo/onlineUsers.do` | `timestamp` |
| 选课学分信息 | POST | `/sys/xsxkapp/student/xkxf.do` | `xh`, `xklcdm`, `xklclx` |
| 引导页读取状态 | GET | `/sys/xsxkapp/student/guideMap.do` | `timestamp`, `studentCode` |
| 引导页标记已读 | POST | `/sys/xsxkapp/student/guideMap.do` | query `studentCode` |
| CAS/统一身份注册 | GET | `/sys/xsxkapp/student/register.do` | `number` |
| 退出登录 | GET | `/sys/xsxkapp/student/logout.do` | `timestamp`, `studentNumber` |
| 认证退出 | GET | `/sys/xsxkapp/student/authlogout.do` | `timestamp` |

登录后需要保留：

- Cookie：用于同源会话。
- 请求头 `token`：登录响应 `data.token`，后续多数接口都要带。
- `studentInfo` 等上下文：Go 客户端不需要模拟 `sessionStorage`，但要保存其中对应字段：学生号、可见轮次列表、当前选择轮次、当前校区、轮次类型、是否开放。

轮次不能写死。每次登录后都应重新读取 `student/<studentCode>.do` 和 `elective/batch.do` 的返回，把当前账号、当前时间点可见的普通/实验/实践等轮次作为运行时数据保存。后续课程查询、可选校验、选课/退选、教材和课表接口都使用用户当前选择的 `batchCode`，不要把某次抓包里看到的轮次数量或名称写入客户端默认值。

### 登录参数构造

前端登录链路在 `static-snapshot/bksxk.nwafu.edu.cn/xsxkapp/static/index.min.js`：

- 密码字段：先取 `getDesKeys()`，再执行 `strEnc(password, key1, key2, key3)`，最后执行 `$.base64.encode(...)` 作为 `loginPwd`。
- `docs/site-map.generated.md` 的 API 入口会把该 `$.get(BaseUrl + "/sys/xsxkapp/student/check/login.do?...")` 解析为 `GET /sys/xsxkapp/student/check/login.do`，可用于核对方法和前端来源。
- `getDesKeys()` 在 `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/index/indexBS.js:143` 和 `static-snapshot/bksxk.nwafu.edu.cn/xsxkapp/static/indexBS.min.js:1`，返回 `['this','password','is']`。
- `strEnc()`/`strDec()` 定义已持久化在 `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/des.min.js`。
- `$.base64.encode()`/`decode()` 定义已持久化在 `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/jquery.base64.min.js`。
- 登录首页实际引用的公网脚本也已保存到 `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/index/index.min.js` 和 `index/indexBS.min.js`，用于和业务脚本快照交叉核对。
- 文字验证码模式：`vodeType == "1"` 时，`verifyCode` 取输入框文本。
- 点选验证码模式：否则读取 `verifyResult` 的 4 个点击坐标，拼成 `left-top,left-top,left-top,left-top`。
- `vtoken` 来自 `student/4/vcode.do` 响应的 `data.token`，验证码图片请求和登录校验都使用同一个 `vtoken`。

## 课程列表查询

课程列表查询通常把实际查询条件塞进一个字符串字段 `querySetting`：

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"campus\":\"<campus>\",\"electiveBatchCode\":\"<batchCode>\",\"isMajor\":\"1\",\"teachingClassType\":\"TJKC\",\"checkConflict\":\"2\",\"checkCapacity\":\"2\",\"queryContent\":\"\"},\"pageSize\":\"10\",\"pageNumber\":\"0\",\"order\":\"\"}"
}
```

常见 `teachingClassType`：

| 类型 | 含义 | 接口 |
| --- | --- | --- |
| `TJKC` | 系统推荐课程 | `POST /sys/xsxkapp/elective/recommendedCourse.do` |
| `FANKC` | 方案内课程 | `POST /sys/xsxkapp/elective/programCourse.do` |
| `FAWKC` | 方案外课程 | `POST /sys/xsxkapp/elective/programCourse.do` |
| `XGXK` | 通识/校公选课 | `POST /sys/xsxkapp/elective/publicCourse.do` |
| `CXKC` | 重修课程 | `POST /sys/xsxkapp/elective/programCourse.do` |
| `TYKC` | 体育课 | `POST /sys/xsxkapp/elective/programCourse.do` |
| `FXKC` | 辅修 | `POST /sys/xsxkapp/elective/programCourse.do`，`isMajor` 为 `0` |
| `QXKC` | 全校课程查询 | `POST /sys/xsxkapp/elective/queryCourse.do` |

`QXKC` 的实测请求体与方案内/推荐课程略有不同：不带 `checkConflict` 和 `checkCapacity`。前端构造出的 JSON 文本里出现过重复 `isMajor` 键；按 JSON 语义保留一个即可。

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"campus\":\"<campus>\",\"electiveBatchCode\":\"<batchCode>\",\"isMajor\":\"1\",\"teachingClassType\":\"QXKC\",\"queryContent\":\"大学英语\"},\"pageSize\":\"10\",\"pageNumber\":\"0\",\"order\":\"\"}"
}
```

`queryCourse.do` 的 `dataList` 是教学班平铺列表；`programCourse.do`、`recommendedCourse.do` 这类接口的 `dataList` 是课程汇总列表，具体教学班在每行的 `tcList` 中。

### 分页与完整列表

课程列表接口都是服务端分页。UI 上“方案内课程”原始列表显示两页，是因为前端默认发：

```json
{
  "pageSize": "10",
  "pageNumber": "0"
}
```

响应包里的 `totalCount` 是筛选条件下的总行数，`dataList.length` 是当前页行数。`pageNumber` 从 `0` 开始：第一页为 `0`，第二页为 `1`。

获取完整课程列表有两种方式：

1. 放大 `pageSize`，例如 `100`、`1000` 或 `10000`，如果后端没有强制上限，第一页可以直接返回完整 `dataList`。
2. 按 `totalCount` 循环分页，直到累计行数达到 `totalCount` 或某页返回空列表。

2026-06-30 实测当前方案内课程：

| `pageSize` | `pageNumber` | `totalCount` | `dataList.length` |
| ---: | ---: | ---: | ---: |
| 10 | 0 | 15 | 10 |
| 100 | 0 | 15 | 15 |
| 1000 | 0 | 15 | 15 |

也就是说，至少对当前 `FANKC` 方案内课程，接口支持通过放大 `pageSize` 一次返回全部课程。为了写成通用客户端，仍建议代码保留分页循环兜底，因为全校课程 `QXKC` 等入口可能有数千行。

2026-06-30 继续实测全校课程 `QXKC` 空关键词查询：

| `pageSize` | `pageNumber` | `totalCount` | `dataList.length` | 响应体大小 | 耗时 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1000 | 0 | 6879 | 1000 | 约 2.4 MB | 约 12 s |
| 10000 | 0 | 6879 | 6879 | 约 17.9 MB | 约 13 s |

所以全校课程接口本身也可以一次返回完整列表，只是返回的是教学班平铺行，数据量明显更大。实现客户端时可以“先大页拉取、再检查 `dataList.length >= totalCount`”，如果没有拿全再按 `pageNumber` 翻页。

注意“完整课程列表”在不同接口中含义不同：

- `programCourse.do`、`recommendedCourse.do`、`publicCourse.do` 返回课程汇总行；每门课的教学班在该行 `tcList[]` 内。
- `queryCourse.do` 返回教学班平铺行；如果需要课程维度列表，需要客户端按 `courseNumber`、`courseName` 聚合。

方案内课程完整列表示例：

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"campus\":\"<campus>\",\"electiveBatchCode\":\"<batchCode>\",\"isMajor\":\"1\",\"teachingClassType\":\"FANKC\",\"checkConflict\":\"2\",\"checkCapacity\":\"2\",\"queryContent\":\"\"},\"pageSize\":\"10\",\"pageNumber\":\"0\",\"order\":\"\"}"
}
```

如果第一页响应 `totalCount=15` 且 `pageSize=10`，还需要继续请求：

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"campus\":\"<campus>\",\"electiveBatchCode\":\"<batchCode>\",\"isMajor\":\"1\",\"teachingClassType\":\"FANKC\",\"checkConflict\":\"2\",\"checkCapacity\":\"2\",\"queryContent\":\"\"},\"pageSize\":\"10\",\"pageNumber\":\"1\",\"order\":\"\"}"
}
```

Go 客户端实现时不要把“点击展开课程”当成拉取下一页。点击课程只是在前端展开当前课程行里的 `tcList`；完整课程列表应通过分页参数拉取。

伪代码：

```go
pageSize := 1000
pageNumber := 0
var all []CourseRow

for {
    resp := PostCourseQuery("FANKC", pageSize, pageNumber, "")
    all = append(all, resp.DataList...)
    if len(all) >= resp.TotalCount || len(resp.DataList) == 0 {
        break
    }
    pageNumber++
}
```

查询辅助接口：

| 用途 | 方法 | 路径 |
| --- | --- | --- |
| 已选课程 | GET | `/sys/xsxkapp/elective/courseResult.do` |
| 退选日志 | GET | `/sys/xsxkapp/elective/returnResults.do` |
| 教学班详情 | GET | `/sys/xsxkapp/publicinfo/queryjxb.do` |
| 教学班容量 | GET | `/sys/xsxkapp/elective/teachingclass/capacity.do` |
| 是否可选 | GET | `/sys/xsxkapp/util/canchoose.do` |
| 实验课列表 | POST | `/sys/xsxkapp/elective/testCourse.do` |
| 所属方案 | POST | `/sys/xsxkapp/elective/course/kcssfa.do` |
| 操作处理状态 | POST | `/sys/xsxkapp/elective/studentstatus.do` |
| 落选课程 | GET | `/sys/xsxkapp/elective/unsuccessful.do` |
| 队列信息 | GET | `/sys/xsxkapp/elective/queryStudentQueue.do` |
| 教材信息 | POST | `/sys/xsxkapp/textbook/queryxsjxbbook.do` |
| 课表已排时间 | GET | `/sys/xsxkapp/elective/teachingTime.do` |
| 课表未安排时间 | GET | `/sys/xsxkapp/elective/noArranged.do` |
| 课程详情 | GET | `/sys/xsxkapp/publicinfo/querykcxx.do` |
| 教师详情 | GET | `/sys/xsxkapp/publicinfo/queryjzg.do` |
| 教师照片 | GET | `/sys/xsxkapp/publicinfo/queryjzgphoto.do` |
| 成绩详情 | POST | `/sys/xsxkapp/student/xscj.do` |
| 公告列表 | GET | `/sys/xsxkapp/publicinfo/notice.do` |
| 公告详情 | GET | `/sys/xsxkapp/publicinfo/notice/view.do` |
| 常见问题 | GET | `/sys/xsxkapp/publicinfo/problem.do` |
| 名人名言/页脚信息 | GET | `/sys/xsxkapp/publicinfo/celebrityfamous.do` |
| 志愿等级字典 | GET | `/sys/xsxkapp/publicinfo/volunteer.do` |
| 辅修筛选年级/院系/专业 | GET | `/sys/xsxkapp/publicinfo/fx/<nj|yx|zy>.do` |
| 跨年级/方案外筛选年级/院系/专业 | GET | `/sys/xsxkapp/publicinfo/zx/<nj|yx|zy>.do` |
| 侧边栏课程搜索 | POST | `/sys/xsxkapp/elective/course.do` |
| 课程可选志愿等级 | GET | `/sys/xsxkapp/elective/course/volunteer.do` |
| 已报志愿静态残留 | GET | `/sys/xsxkapp/elective/volunteered.do` |

`queryContent` 的筛选 token 由前端按类型拼接：

| 类型 | token |
| --- | --- |
| `TJKC`/`FANKC`/`CXKC`/`TYKC` | `KCXZ`, `KCLB` |
| `FAWKC` | `KCXZ`, `KCLB`, `ZXNJ`, `ZXYX`, `ZXZY` |
| `XGXK` | `XGXKLBDM`, `KCBK` |
| `FXKC` | `KCXZ`, `KCLB`, `FXNJ`, `FXYX`, `FXZY` |
| `QXKC` | `XGXKLBDM`, `KKDWDM`, `XFLB` |

## 方案内教学班卡片模型

方案内课程行点击后展开 `tcList`，不是重新请求详情列表。前端把每个教学班渲染为一个卡片，卡片根节点 id 为 `<teachingClassID>_courseDiv`。

核心字段映射：

| 字段 | 用途 |
| --- | --- |
| `teachingClassID` | 选课/退选/教材/校验请求里的教学班 id |
| `courseNumber`, `courseName`, `courseIndex` | 课程号、课程名、课序号 |
| `engpCode`, `engpName` | 英语/体育等分组或方向标签 |
| `teacherName` | 卡片标题教师 |
| `teachingPlace` | 上课时间地点展示文本 |
| `classCapacity`, `numberOfSelected`, `isFull` | 容量和“可选/不可选”状态 |
| `isConflict`, `conflictDesc` | 冲突标签和冲突说明 |
| `isChoose`, `chooseVolunteer` | 已选状态；`isChoose="1"` 时显示已选/退选 |
| `hasTest`, `testTeachingClassID` | 是否包含实验课及实验课教学班 |
| `needOrderBook`, `needBook`, `hasBook` | 教材订购状态 |
| `capacitySuffix` | 容量刷新请求的后缀参数 |

以 `大学英语（Ⅲ）` 为例，方案内接口返回一个课程汇总行，`number=30`，`tcList` 为 30 个可渲染教学班。已选教学班卡片显示“已选”和“退选”；未选教学班仍有隐藏的确认/取消控件，点击卡片或选择动作时才进入确认态。

运行期字段摘要见 [docs/api.runtime.md](api.runtime.md)。

## 页面路由

这些是前端页面入口，不一定都有独立业务数据；Go 客户端通常不需要请求页面 HTML，但离线复刻页面逻辑时要知道入口与业务接口的对应关系。

机器可读入口见 [page.manifest.generated.json](page.manifest.generated.json)。该文件来自静态站点地图，和业务 JSON API manifest 分开维护：页面入口用于还原前端路由和弹窗片段，业务请求仍以 `api.manifest.generated.json` / `api.requests.generated.json` 为准。

| 页面 | 用途 |
| --- | --- |
| `/sys/xsxkapp/*default/index.do` | 首页/登录后概览 |
| `/sys/xsxkapp/*default/grablessons.do?token=<token>` | 抢课/正选主界面 |
| `/sys/xsxkapp/*default/curriculavariable.do?token=<token>` | 普通课表/变量轮次入口 |
| `/sys/xsxkapp/*default/expcurriculavariable.do?token=<token>` | 实践/实验轮次入口 |
| `/sys/xsxkapp/*default/curriculum.do` | 我的课表页面 |
| `/sys/xsxkapp/*default/expcurriculum.do` | 实践课表页面 |
| `/sys/xsxkapp/*default/selectedcourse.do` | 已选课程弹窗/片段 |
| `/sys/xsxkapp/*default/selectedvolunteer.do` | 已选志愿片段 |
| `/sys/xsxkapp/*default/departurelog.do` | 退选日志片段 |
| `/sys/xsxkapp/*default/coursedetail.do?courseNum=<courseNumber>` | 课程详情页面；实际业务接口为 `querykcxx.do` |
| `/sys/xsxkapp/*default/jcdetail.do?jxbid=<teachingClassID>` | 教材信息页面 |
| `/sys/xsxkapp/*default/jssimple.do?jsh=<teacherCode>` | 教师详情页面 |
| `/sys/xsxkapp/*default/jssimple1.do?jsh=<teacherCode>` | 教师详情备用入口；前端按教师类型选择 |
| `/sys/xsxkapp/*default/scoredetail.do` | 成绩详情页面 |
| `/sys/xsxkapp/*default/publicinfo.do?type=notice|problem` | 公告/常见问题列表 |
| `/sys/xsxkapp/*default/content.do?id=<wid>` | 公告内容页 |

## 其他查询/字典接口

### 轮次开放校验

多个操作前会同步调用：

```http
POST /sys/xsxkapp/elective/batchisopen.do
token: <token>

xklcdm=<batchCode>
```

用途：在选课、退选、教材等动作前确认当前轮次仍开放。Go 客户端应在提交前调用一次，避免用过期轮次构造请求。

### 引导页状态

```http
GET /sys/xsxkapp/student/guideMap.do?timestamp=<timestamp>&studentCode=<studentCode>
POST /sys/xsxkapp/student/guideMap.do?studentCode=<studentCode>
```

GET 返回 `code=2` 表示未读，前端显示引导页并随后 POST 标记已读。该 POST 改变“是否读过引导页”的轻量状态，不影响选课结果。

### 首页聚合信息

```http
GET /sys/xsxkapp/publicinfo.do?timestamp=<timestamp>&pageSize=10&pageNumber=1
```

首页一次返回通知、常见问题、咨询方式、停课/停止说明、名人名言等聚合数据。前端从响应 `data` 中读取：

```text
noticeList, commonProblemList, consultMethod, celebrityFamousList, stopInfo
```

### 志愿等级字典

```http
GET /sys/xsxkapp/publicinfo/volunteer.do?timestamp=<timestamp>
```

返回 `dataList[]`，前端使用 `grade` 和 `name` 渲染志愿标签颜色和文案。当前正选轮次里 `chooseVolunteer` 常见为 `1`。

### 筛选字典

```http
GET /sys/xsxkapp/publicinfo/fx/nj.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/fx/yx.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/fx/zy.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/zx/nj.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/zx/yx.do?timestamp=<timestamp>
GET /sys/xsxkapp/publicinfo/zx/zy.do?timestamp=<timestamp>
```

`fx` 用于辅修筛选，`zx` 用于方案外/跨年级类筛选。前端把这些筛选项拼进 `queryContent`。

### 课程辅助查询

```http
GET /sys/xsxkapp/elective/course/volunteer.do?timestamp=<timestamp>
GET /sys/xsxkapp/elective/volunteered.do?timestamp=<timestamp>
```

静态源码里 `queryCourse()` 把 `/elective/course.do` 写成 GET：

```http
GET /sys/xsxkapp/elective/course.do?timestamp=<timestamp>&querySetting=<urlencoded-json>
token: <token>
```

2026-06-30 运行期实测 GET 不返回业务 JSON；POST 才是可用的课程搜索业务接口：

```http
POST /sys/xsxkapp/elective/course.do
token: <token>
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```

请求体仍然是标准 `querySetting`：

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"campus\":\"<campus>\",\"electiveBatchCode\":\"<batchCode>\",\"isMajor\":\"1\",\"teachingClassType\":\"FANKC\",\"checkConflict\":\"2\",\"checkCapacity\":\"2\",\"queryContent\":\"\"},\"pageSize\":\"100\",\"pageNumber\":\"0\",\"order\":\"\"}"
}
```

`course.do` 返回课程汇总行，字段形态与 `programCourse.do` / `recommendedCourse.do` 相同。实测 `TJKC`、`FANKC`、`TYKC` 可返回数据；`FAWKC`、`XGXK`、`CXKC`、`FXKC` 按当前轮次开放状态返回未开放；`QXKC` 返回空列表。全校课程仍应使用 `queryCourse.do`。

`course/volunteer.do` 用于查询某门课在志愿选择时可选的志愿等级。GET 参数必须包含 `queryParam`，且 JSON 内部需要包一层 `data`：

```http
GET /sys/xsxkapp/elective/course/volunteer.do?timestamp=<timestamp>&queryParam=<urlencoded-json>
token: <token>
```

```json
{
  "queryParam": "{\"data\":{\"studentCode\":\"<studentCode>\",\"electiveBatchCode\":\"<batchCode>\",\"courseNumber\":\"<courseNumber>\"}}"
}
```

实测返回 `code=1`，`dataList[]` 字段为 `grade, isUse, name, wid`。

`volunteered.do` 只在首页静态脚本 `indexBS.min.js` 中发现函数定义；当前部署对 `/sys/xsxkapp/elective/volunteered.do` 返回 404。`selectedvolunteer.do` 片段本身不引用该接口，已选志愿/已选课程弹窗实际复用 `selectedcourse.js` 的 `courseResult.do`。实现 Go 客户端时把它作为静态残留记录，不作为当前正选流程必需接口。

### 课程所属方案

```http
POST /sys/xsxkapp/elective/course/kcssfa.do
token: <token>
Content-Type: application/x-www-form-urlencoded
```

```json
{
  "querySetting": "{\"data\":{\"studentCode\":\"<studentCode>\",\"electiveBatchCode\":\"<batchCode>\",\"courseNumber\":\"<courseNumber>\"},\"pageSize\":\"10\",\"pageNumber\":\"0\"}"
}
```

响应 `dataList[]` 字段用于“课程所属方案”弹窗：

```text
campusName, type, courseNatureName, departmentName
```

## 页面信息接口

### 教师详情

```http
GET /sys/xsxkapp/*default/jssimple.do?jsh=<teacherCode>
GET /sys/xsxkapp/publicinfo/queryjzg.do?jsh=<teacherCode>
GET /sys/xsxkapp/publicinfo/queryjzgphoto.do?jsh=<teacherCode>
```

`queryjzg.do` 返回 `data` 对象，字段以大写统计项为主，如教师基本信息、授课学时、教材、教研项目、论文、获奖、会议、兼职、荣誉等计数。

### 成绩详情

```http
GET /sys/xsxkapp/*default/scoredetail.do
POST /sys/xsxkapp/student/xscj.do
```

请求体：

```json
{
  "electiveBatchCode": "<batchCode>",
  "studentCode": "<studentCode>"
}
```

页面源码按 `schoolTermName` 分组展示 `courseNumber`、`courseName`、`credit`、`score`、`retakeTypeName`。本次运行期返回 `code=0`，原因是成绩菜单未开放。

### 公告与常见问题

```http
GET /sys/xsxkapp/*default/publicinfo.do?type=notice
GET /sys/xsxkapp/publicinfo/notice.do?timestamp=<timestamp>&pageSize=<pageSize>&pageNumber=<pageNumber>
GET /sys/xsxkapp/*default/content.do?id=<wid>
GET /sys/xsxkapp/publicinfo/notice/view.do?timestamp=<timestamp>&wid=<wid>
GET /sys/xsxkapp/*default/publicinfo.do?type=problem
GET /sys/xsxkapp/publicinfo/problem.do?timestamp=<timestamp>
```

公告列表和公告详情使用字段 `title`、`publishTime`、`timeDescription`、`filename`、`content`、`wid`。常见问题列表使用 `title`、`publishTime`、`timeDescription`、`content`、`serialNumber`、`wid`。

`content.js` 中有附件入口逻辑：如果公告详情 `data.filename` 非空，页面会显示 `.home-downloadfile .downloadfile`，并把 `data.wid` 拼到该链接已有 `href` 后。当前快照没有包含带附件公告的实际 `href`，因此附件下载作为页面链接行为记录，尚未归入已验证 JSON API。

## 状态变更接口

这些接口会改变选课结果；当前只整理字段、调用链和本地 mock 参数，不为获取响应执行真实提交。

可用 `npm run request-examples` 生成不会发送网络请求的本地参数样例。

### 添加选课

源码位置：`grablessons.js` 的 `buildAddVolunteerParam()` 和 `addVolunteer()`。

```http
POST /sys/xsxkapp/elective/volunteer.do
token: <sessionStorage.token>
Content-Type: application/x-www-form-urlencoded
```

表单字段：

```json
{
  "addParam": "{\"data\":{\"operationType\":\"1\",\"studentCode\":\"<studentCode>\",\"electiveBatchCode\":\"<batchCode>\",\"teachingClassId\":\"<teachingClassId>\",\"isMajor\":\"1\",\"campus\":\"<campus>\",\"teachingClassType\":\"<teachingClassType>\"}}"
}
```

`needBook` 和 `testTeachingClassID` 在字段层面是可省略字段，但在业务层面不是简单“可选项”。是否必须携带由教学班字段决定：

| 条件 | 前端动作 | 提交字段 |
| --- | --- | --- |
| `hasTest != "1"` 且无教材征订 | 直接提交 | 不带 `testTeachingClassID` / `needBook` |
| `hasTest == "1"` | 先调用 `testCourse.do`，让用户选择实验课教学班 | 必带 `testTeachingClassID=<实验教学班ID>` |
| 系统开启教材征订且教学班 `hasBook == "1"` | 先调用 `testCourse.do`，用响应 `map` 渲染教材选择 | 必带 `needBook=<教材选择串>` |
| 同时有实验课和教材 | 同一个弹窗内选择实验教学班和教材 | 同时带 `testTeachingClassID` 与 `needBook` |

教材选择串来自 `grablessons.js` 的 `getSelectJcxx()`：多个教材用逗号拼接；订购教材为 `<bookCode>`，不订购教材为 `<bookCode>-<reasonCode>`。前端在提交前会检查不订购原因，若仍为 `***` 则不会发起 `volunteer.do`。

也就是说，Go 客户端构造 `volunteer.do` 请求时必须先看课程/教学班行：

- `hasTest == "1"`：不能直接提交理论课教学班，必须先用 `testCourse.do` 查出可选实验教学班并把选择结果放入 `testTeachingClassID`。
- `hasBook == "1"` 且当前轮次允许教材征订：不能只提交教学班 id，必须先处理教材列表，把订购/不订购结果放入 `needBook`。
- 没有实验课、没有教材征订时，才能使用最短 `addParam`。

本地构造示例：

```bash
npm run request-examples
```

输出中的 `addVolunteer`、`addVolunteerWithTest`、`addVolunteerWithBook`、`addVolunteerWithTestAndBook` 分别对应上述四类提交形态。

添加成功后前端轮询：

```http
POST /sys/xsxkapp/elective/studentstatus.do
```

请求体：

```json
{
  "studentCode": "<studentCode>"
}
```

### 退选

源码位置：`selectedcourse.js` / `grablessons.js` 的 `deleteVolunteer()` 和 `selectedcourseBS.js` 的 `deleteVolunteerResult()`。

```http
GET /sys/xsxkapp/elective/deleteVolunteer.do?timestamp=<timestamp>
token: <sessionStorage.token>
```

参数字段：

```json
{
  "deleteParam": "{\"data\":{\"operationType\":\"2\",\"studentCode\":\"<studentCode>\",\"electiveBatchCode\":\"<batchCode>\",\"teachingClassId\":\"<teachingClassId>\",\"isMajor\":\"1\"}}"
}
```

退选成功后同样轮询：

```http
POST /sys/xsxkapp/elective/studentstatus.do
```

### 教材订退

这些也会修改状态：

| 用途 | 方法 | 路径 |
| --- | --- | --- |
| 订购教材 | POST | `/sys/xsxkapp/textbook/addbook.do` |
| 退订教材 | POST | `/sys/xsxkapp/textbook/modifybook.do` |

教材查询：

```http
POST /sys/xsxkapp/textbook/queryxsjxbbook.do
```

请求体：

```json
{
  "xh": "<studentCode>",
  "jxbid": "<teachingClassId>",
  "xklcdm": "<batchCode>"
}
```

订购教材请求体：

```json
{
  "xh": "<studentCode>",
  "jxbid": "<teachingClassId>",
  "xklcdm": "<batchCode>"
}
```

退订/修改教材请求体：

```json
{
  "xh": "<studentCode>",
  "jxbid": "<teachingClassId>",
  "xklcdm": "<batchCode>",
  "jcxx": "<bookCode-or-bookCode-reason,...>",
  "czlx": "0|1"
}
```

### 落选确认

前端在落选提醒弹窗中把 `unsuccessful.do` 返回行的 `wid` 用逗号拼成 `wids`：

```http
GET /sys/xsxkapp/elective/submit/unsuccessful.do?wids=<wid,...>&studentCode=<studentCode>
```

## 当前缺口

- 方案内、方案外、公选、重修、体育、辅修、全校课程等入口仍需要补运行期样例。
- 教师详情、成绩详情页面仍需要补运行期样例；课程详情、教学班详情、退选日志、落选课程已完成只读接口验证。
- `volunteer.do`、`deleteVolunteer.do`、教材订退等写操作目前以静态源码和本地参数构造为主，缺少真实响应体。
