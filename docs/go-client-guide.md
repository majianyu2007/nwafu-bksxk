# Go 客户端实现指南

本文把仓库里的 API 笔记整理成 Go 客户端实现顺序。Go 侧优先读取 [client.contract.generated.json](client.contract.generated.json)；写 struct 和构造器时看 [go-client-catalog.generated.md](go-client-catalog.generated.md)。完整字段仍以 [api.notes.md](api.notes.md)、[api.runtime.md](api.runtime.md)、[api.coverage.md](api.coverage.md)、[api.manifest.generated.json](api.manifest.generated.json)、[api.requests.generated.json](api.requests.generated.json)、[api.response-schemas.generated.json](api.response-schemas.generated.json) 和 [page.manifest.generated.json](page.manifest.generated.json) 为准。前端静态源码证据见 [static-assets.manifest.generated.json](static-assets.manifest.generated.json) 和 `../static-snapshot/`；页面结构可看 `../snapshots/grablessons.sanitized.html`。

## 基础 HTTP 模型

完整业务 URL 由站点根和接口路径拼接：

```text
https://bksxk.nwafu.edu.cn/xsxkapp + /sys/xsxkapp/...
```

客户端需要：

- `http.Client` 配 `cookiejar.Jar`，保留登录会话 Cookie。
- 登录成功后保存响应里的 `token`，后续登录态接口统一加请求头 `token: <token>`。
- POST 表单使用 `application/x-www-form-urlencoded; charset=UTF-8`。
- 课程查询类接口把 JSON 字符串放进表单字段 `querySetting`。
- 志愿等级辅助接口 `course/volunteer.do` 把 JSON 字符串放进查询字段 `queryParam`。

通用响应包可以先按宽松结构解析：

```go
type Envelope[T any] struct {
    Code       string          `json:"code"`
    Msg        any             `json:"msg"`
    Data       T               `json:"data"`
    DataList   json.RawMessage `json:"dataList"`
    TotalCount int             `json:"totalCount"`
    Map        json.RawMessage `json:"map"`
    KeyExpired bool            `json:"keyExpired"`
    Timestamp  int64           `json:"timestamp"`
}
```

实际写客户端时，`dataList` 建议先用 `json.RawMessage` 接住，再按接口解成课程行、教学班行、公告行等结构。

## 登录与会话初始化

最小流程：

1. `GET /sys/xsxkapp/student/4/vcode.do?timestamp=<ts>` 获取验证码 token。
2. `GET /sys/xsxkapp/student/vcode/image.do?vtoken=<vtoken>` 获取验证码图片。
3. `GET /sys/xsxkapp/student/check/login.do?...` 提交账号、密码、验证码和 `vtoken`。
4. 保存登录响应里的 `token`。
5. `GET /sys/xsxkapp/student/<studentCode>.do?timestamp=<ts>` 获取学生信息、可见轮次和前端当前选择轮次。
6. `GET /sys/xsxkapp/elective/batch.do?timestamp=<ts>` 刷新登录态可见轮次列表。
7. 保存轮次列表、当前选择轮次 `electiveBatch.code`、当前校区 `currentCampus.code`、学生号、轮次类型等上下文。
8. 按需调用 `dictionary.do`、`sysparam.do`、`xkxf.do`、`batchisopen.do` 补齐页面所需上下文。

前端依赖 `sessionStorage`，Go 客户端不需要模拟浏览器存储，但要把同等字段保存到自己的 `Session` 结构里。

登录参数的前端证据：

- `static-snapshot/bksxk.nwafu.edu.cn/xsxkapp/static/index.min.js` 中，登录函数把明文密码先传给 `strEnc(password, key1, key2, key3)`，再用 `$.base64.encode(...)` 生成 `loginPwd`。
- `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/index/indexBS.js:143` 的 `getDesKeys()` 返回 `['this','password','is']`。
- `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/des.min.js` 保存了 `strEnc()`/`strDec()` 的站点实现。
- `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/jquery.base64.min.js` 保存了 `$.base64.encode()`/`decode()` 的站点实现。
- `static-snapshot/xkres.nwafu.edu.cn/products/jwfw/xsxkapp/public/js/index/index.min.js` 和 `index/indexBS.min.js` 是登录首页实际引用脚本，可和 `bksxk.nwafu.edu.cn/xsxkapp/static/` 下的业务脚本交叉核对。
- `vodeType == "1"` 时 `verifyCode` 是输入框文本；否则从 4 个点选坐标拼成 `left-top,left-top,left-top,left-top`。
- `vtoken` 来自验证码 token 接口响应，随后同时用于验证码图片 URL 和登录校验参数。

Go 实现 `loginPwd` 时应按前端顺序复刻：`strEnc(plainPassword, "this", "password", "is")`，再对结果做 `$.base64.encode()` 同等编码。

```go
type ElectiveBatch struct {
    Code       string
    Name       string
    BatchType  string
    CanSelect  bool
    BeginTime  time.Time
    EndTime    time.Time
    TacticCode string
}

type Session struct {
    Token          string
    StudentCode    string
    CampusCode     string
    VisibleBatches []ElectiveBatch
    CurrentBatch   ElectiveBatch
    ElectiveIsOpen bool
}
```

`VisibleBatches` 必须来自本次登录后的接口返回。不要把抓包时看到的轮次数量、名称或日期编译进客户端；一年内会出现多个选课轮次，课程查询和提交都应使用用户当前选择的 `CurrentBatch.Code`。

## 请求构造

课程查询参数：

```go
type CourseQueryData struct {
    StudentCode       string `json:"studentCode"`
    Campus            string `json:"campus,omitempty"`
    ElectiveBatchCode string `json:"electiveBatchCode"`
    IsMajor           string `json:"isMajor"`
    TeachingClassType string `json:"teachingClassType"`
    CheckConflict     string `json:"checkConflict,omitempty"`
    CheckCapacity     string `json:"checkCapacity,omitempty"`
    QueryContent      string `json:"queryContent"`
}

type QuerySetting struct {
    Data       CourseQueryData `json:"data"`
    PageSize   string          `json:"pageSize"`
    PageNumber string          `json:"pageNumber"`
    Order      string          `json:"order,omitempty"`
}
```

构造方式：

```go
payload, _ := json.Marshal(QuerySetting{Data: data, PageSize: "1000", PageNumber: "0"})
form := url.Values{}
form.Set("querySetting", string(payload))
```

课程类型到接口的映射：

| 类型 | 接口 |
| --- | --- |
| `TJKC` | `POST /sys/xsxkapp/elective/recommendedCourse.do` |
| `FANKC` / `FAWKC` / `CXKC` / `TYKC` / `FXKC` | `POST /sys/xsxkapp/elective/programCourse.do` |
| `XGXK` | `POST /sys/xsxkapp/elective/publicCourse.do` |
| `QXKC` | `POST /sys/xsxkapp/elective/queryCourse.do` |

`QXKC` 不带 `checkConflict` / `checkCapacity`，返回教学班平铺行。其他课程列表通常返回课程汇总行，每行 `tcList[]` 是可选教学班卡片。

分页规则：

- `pageNumber` 从 `0` 开始。
- 响应 `totalCount` 是筛选后总数。
- 先用较大 `pageSize` 拉取，若 `len(dataList) < totalCount` 再递增 `pageNumber` 继续。

## 选课提交流程

添加课程请求：

```http
POST /sys/xsxkapp/elective/volunteer.do
```

表单字段：

```json
{
  "addParam": "{\"data\":{\"operationType\":\"1\",\"studentCode\":\"<studentCode>\",\"electiveBatchCode\":\"<batchCode>\",\"teachingClassId\":\"<teachingClassId>\",\"isMajor\":\"1\",\"campus\":\"<campus>\",\"teachingClassType\":\"<teachingClassType>\"}}"
}
```

提交前必须根据教学班字段选择分支：

| 教学班字段 | Go 客户端动作 | `addParam` 字段 |
| --- | --- | --- |
| `hasTest != "1"` 且无教材征订 | 直接提交 | 最小字段 |
| `hasTest == "1"` | 先 `POST /sys/xsxkapp/elective/testCourse.do`，选择实验教学班 | `testTeachingClassID` |
| `hasBook == "1"` 且当前轮次允许教材征订 | 用 `testCourse.do` 响应 `map` 构造教材选择串 | `needBook` |
| 两者都有 | 同时处理实验教学班和教材 | `testTeachingClassID` + `needBook` |

教材选择串格式：

```text
订购:     <bookCode>
不订购:   <bookCode>-<reasonCode>
多本教材: <item>,<item>,...
```

提交后轮询：

```http
POST /sys/xsxkapp/elective/studentstatus.do
studentCode=<studentCode>
```

前端在成功后刷新 `courseResult.do` 和教学班容量。

## 退选与教材

退选：

```http
GET /sys/xsxkapp/elective/deleteVolunteer.do?timestamp=<ts>
deleteParam={"data":{"operationType":"2",...}}
```

教材查询：

```http
POST /sys/xsxkapp/textbook/queryxsjxbbook.do
xh=<studentCode>&jxbid=<teachingClassId>&xklcdm=<batchCode>
```

教材订退：

| 动作 | 接口 | 字段 |
| --- | --- | --- |
| 订购教材 | `POST /sys/xsxkapp/textbook/addbook.do` | `xh`, `jxbid`, `xklcdm` |
| 修改/退订教材 | `POST /sys/xsxkapp/textbook/modifybook.do` | `xh`, `jxbid`, `xklcdm`, `jcxx`, `czlx` |

## 机器合同用法

[client.contract.generated.json](client.contract.generated.json) 是 Go 客户端最省事的机器入口。它把每个业务端点的清单、请求样例、响应字段摘要合成一条 `endpointContract[]`，并把页面/片段入口放在 `pageContract[]`。

```go
type ClientContract struct {
    EndpointCount int `json:"endpointCount"`
    PageCount     int `json:"pageCount"`
    EndpointContract []struct {
        ID              string          `json:"id"`
        Section         string          `json:"section"`
        Status          string          `json:"status"`
        Method          string          `json:"method"`
        Endpoint        string          `json:"endpoint"`
        StateChanging   bool            `json:"stateChanging"`
        Description     string          `json:"description"`
        Request         json.RawMessage `json:"request"`
        Response        json.RawMessage `json:"response"`
        ExecutionPolicy string          `json:"executionPolicy"`
    } `json:"endpointContract"`
    PageContract []PageEntry `json:"pageContract"`
}
```

`executionPolicy=="serialize-only"` 表示只能在本地构造和测试请求，不应拿真实系统执行；`read-only-callable` 表示是查询类或静态残留接口，仍要按对应 `status` 判断是否有运行期响应。

## Manifest 用法

[api.manifest.generated.json](api.manifest.generated.json) 是从覆盖矩阵生成的机器可读入口表，包含：

- `id`
- `section`
- `status`
- `method`
- `endpoint`
- `description`
- `stateChanging`

Go 侧可以用它生成常量或覆盖测试：

```go
type Manifest struct {
    EndpointCount int `json:"endpointCount"`
    Endpoints []struct {
        ID            string `json:"id"`
        Section       string `json:"section"`
        Status        string `json:"status"`
        Method        string `json:"method"`
        Endpoint      string `json:"endpoint"`
        Description   string `json:"description"`
        StateChanging bool   `json:"stateChanging"`
    } `json:"endpoints"`
}
```

请求参数样例见 [api.requests.generated.json](api.requests.generated.json)。它和 manifest 一一对应，每条记录包含：

- `method`
- `endpoint`
- `stateChanging`
- `request.headers`
- `request.pathParams`
- `request.query`
- `request.form`
- `request.variants`

Go 侧可把它当成测试夹具：先检查所有 `stateChanging=false` 的请求都能构造出 URL 和表单，再对 `stateChanging=true` 的请求只做本地序列化测试。

响应字段摘要见 [api.response-schemas.generated.json](api.response-schemas.generated.json)。它适合用来起草 Go struct，但不要把 `write-not-executed` 的端点当成已有真实响应；这些接口只确认了请求构造。

页面和片段入口见 [page.manifest.generated.json](page.manifest.generated.json)。Go 客户端复刻业务逻辑时通常不需要请求这些 HTML 页面，但完整复刻前端导航、详情页和弹窗时可以用它还原路由：

```go
type PageEntry struct {
    ID           string   `json:"id"`
    Endpoint     string   `json:"endpoint"`
    Kind         string   `json:"kind"`
    Method       string   `json:"method"`
    RouteParams  []string `json:"routeParams"`
    Source       string   `json:"source"`
    FunctionName string   `json:"functionName"`
}
```

维护仓库时运行：

```bash
npm run site-map
npm run static-assets
npm run api-manifest
npm run api-requests
npm run page-manifest
npm run response-schemas
npm run client-contract
npm run coverage-check
npm run endpoint-audit
npm run go-catalog
npm run offline-snapshots
npm test
```

如果站点地图出现新 API，但覆盖矩阵没有分类，`coverage-check` 会失败。
