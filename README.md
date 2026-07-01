# BKSXK API Research

本仓库用于整理 `bksxk.nwafu.edu.cn` 选课系统的页面逻辑、API 入口、请求字段和离线快照。目标是在选课系统关闭后，仍然可以继续研究选课提交逻辑和请求构造。

当前仓库已经保存了登录首页资源、登录后页面快照、主要前端脚本、运行期接口日志和自动生成的接口地图；`artifacts/` 是本地原始采集产物，不进入 git。可公开复用的静态资源已经固化到 `static-snapshot/`，不用每次重新下载远端 JS/CSS/图片。

## 文档入口

- [docs/api.notes.md](docs/api.notes.md)：人工整理的核心 API、参数字段和前端来源。
- [docs/api.runtime.md](docs/api.runtime.md)：登录后通过 MCP Playwright 验证的只读 API 字段摘要。
- [docs/api.coverage.md](docs/api.coverage.md)：接口覆盖矩阵，区分运行期已验证、静态已定位、写操作未执行和待复现分支。
- [docs/endpoint-inventory.audit.generated.md](docs/endpoint-inventory.audit.generated.md)：端点库存审计，把静态快照、运行期日志、覆盖矩阵和客户端合同对齐，检查是否有漏记接口。
- [docs/endpoint-inventory.audit.generated.json](docs/endpoint-inventory.audit.generated.json)：端点库存审计的机器可读版本。
- [docs/api.manifest.generated.json](docs/api.manifest.generated.json)：从覆盖矩阵生成的机器可读接口清单，可供 Go 侧生成常量或测试清单。
- [docs/api.requests.generated.json](docs/api.requests.generated.json)：逐端点请求构造样例，和 manifest 一一对应。
- [docs/api.response-schemas.generated.json](docs/api.response-schemas.generated.json)：逐端点响应字段摘要，和 manifest 一一对应。
- [docs/static-assets.manifest.generated.json](docs/static-assets.manifest.generated.json)：可提交静态资源快照清单，包含本地路径、来源 URL、大小和 SHA-256。
- [docs/offline-snapshots.manifest.generated.json](docs/offline-snapshots.manifest.generated.json)：可提交离线页面快照清单，校验 HTML 快照和本地静态资源引用。
- [docs/page.manifest.generated.json](docs/page.manifest.generated.json)：从静态站点地图生成的页面/片段入口清单。
- [docs/client.contract.generated.json](docs/client.contract.generated.json)：Go 客户端最方便读取的统一合同，合并接口清单、请求样例、响应字段和页面入口。
- [docs/go-client-catalog.generated.md](docs/go-client-catalog.generated.md)：Go 实现字段目录，逐端点列出请求字段、表单内 JSON 路径、响应字段、执行策略和模型提示。
- [docs/go-client-catalog.generated.json](docs/go-client-catalog.generated.json)：Go 实现字段目录的机器可读版本。
- [docs/go-client-guide.md](docs/go-client-guide.md)：按 Go 客户端实现顺序整理的会话、请求构造、分页、选课提交和 manifest 用法。
- [docs/site-map.generated.md](docs/site-map.generated.md)：从持久化业务脚本快照提取的页面、接口、函数索引。
- [docs/site-map.generated.json](docs/site-map.generated.json)：站点地图结构化 JSON，供页面清单和客户端合同生成脚本读取。
- [docs/api.generated.md](docs/api.generated.md)：从运行期 `network.jsonl` 生成的接口摘要。
- [docs/研究流程.md](docs/%E7%A0%94%E7%A9%B6%E6%B5%81%E7%A8%8B.md)：本地采集环境和产物说明。
- [scripts/request-builders.mjs](scripts/request-builders.mjs)：本地构造查询、选课、退选、状态轮询参数，不发送请求。
- [snapshots/grablessons.sanitized.html](snapshots/grablessons.sanitized.html)：脱敏后的选课页面离线 HTML，脚本禁用，资源指向本地 `static-snapshot/`。
- [snapshots/index.sanitized.html](snapshots/index.sanitized.html)：脱敏后的登录首页离线 HTML，保留验证码、登录按钮和登录依赖脚本引用，脚本禁用，资源指向本地 `static-snapshot/`。

课程列表的完整拉取方式见 [docs/api.notes.md](docs/api.notes.md#分页与完整列表)：`querySetting.pageNumber` 从 `0` 开始分页。当前实测 `FANKC` 方案内课程 `pageSize=1000` 可一次取完，`QXKC` 全校课程空关键词 `pageSize=10000` 可一次返回 `6879/6879` 条教学班平铺行。

选课提交参数不能只看教学班 id。若教学班 `hasTest=="1"`，提交 `volunteer.do` 前必须先通过 `testCourse.do` 选择实验教学班并携带 `testTeachingClassID`；若教学班需要教材征订，还必须携带 `needBook` 教材选择串。详见 [docs/api.notes.md](docs/api.notes.md#添加选课)。

## 已定位的核心接口

| 模块 | 方法 | 路径 | 说明 |
| --- | --- | --- | --- |
| 选课轮次 | GET | `/sys/xsxkapp/elective/batch.do` | 登录态可见轮次列表 |
| 选课结果 | GET | `/sys/xsxkapp/elective/courseResult.do` | 已选课程 |
| 推荐课程 | POST | `/sys/xsxkapp/elective/recommendedCourse.do` | 系统推荐课程列表 |
| 方案内课程 | POST | `/sys/xsxkapp/elective/programCourse.do` | 培养方案内课程列表 |
| 公选课程 | POST | `/sys/xsxkapp/elective/publicCourse.do` | 通识/校公选课列表 |
| 通用课程查询 | POST | `/sys/xsxkapp/elective/queryCourse.do` | 全校课程查询 |
| 教学班详情 | GET | `/sys/xsxkapp/publicinfo/queryjxb.do` | 教学班排课、教师等信息 |
| 教学班容量 | GET | `/sys/xsxkapp/elective/teachingclass/capacity.do` | 容量/余量 |
| 可选校验 | GET | `/sys/xsxkapp/util/canchoose.do` | 冲突、容量等选课前校验 |
| 选课提交 | POST | `/sys/xsxkapp/elective/volunteer.do` | 添加课程，字段见 `addParam` |
| 退选提交 | GET | `/sys/xsxkapp/elective/deleteVolunteer.do` | 退选课程，字段见 `deleteParam` |
| 操作状态 | POST | `/sys/xsxkapp/elective/studentstatus.do` | 添加/退选后的处理状态轮询 |
| 教材订购 | POST | `/sys/xsxkapp/textbook/addbook.do` | 订购教材 |
| 教材退订 | POST | `/sys/xsxkapp/textbook/modifybook.do` | 退订教材 |

完整列表以 [docs/site-map.generated.md](docs/site-map.generated.md) 为准，字段结构以 [docs/api.notes.md](docs/api.notes.md) 为准。

## 覆盖状态

| 范围 | 当前状态 | 下一步 |
| --- | --- | --- |
| 登录与初始化 | 已记录验证码、登录校验、学生信息、字典、系统参数、在线人数 | 补充各响应字段含义 |
| 推荐课程 | 已有运行期请求、字段摘要和静态参数构造 | 补排序字段的实际取值 |
| 方案内/方案外/公选/重修/体育/辅修/全校课程 | 已验证各入口的接口映射；已补 `大学英语` 的全校查询返回和方案内教学班卡片展开 | 补有数据入口的更多筛选组合 |
| 已选课程 | 已记录 `courseResult.do` 响应字段和教材相关接口 | 补教材有数据时的响应行字段 |
| 课程详情/教学班详情/教师详情 | 已验证课程详情、教学班详情、容量、可选校验、教师详情字段 | 补教师详情有数据时的展示样例 |
| 落选课程/退选日志 | 已验证 `unsuccessful.do`、`returnResults.do`、队列接口 | 等有数据时补行字段 |
| 选课/退选提交 | 前端请求构造已定位，可本地生成参数 | 不为获取响应而执行真实提交 |
| 教材订退 | 前端接口已定位 | 补请求字段和前端调用链 |
| 成绩/课表页面 | 已验证课表 `teachingTime.do`、`noArranged.do`；成绩接口 `xscj.do` 返回菜单未开放 | 成绩开放时补行字段 |
| 公告/常见问题 | 已验证 `notice.do`、`notice/view.do`、`problem.do` 和内容页 | 补附件下载接口 |

## 本地命令

```bash
npm install
npm test
npm run api-manifest
npm run api-requests
npm run page-manifest
npm run response-schemas
npm run client-contract
npm run coverage-check
npm run endpoint-audit
npm run go-catalog
npm run offline-snapshots
npm run static-assets
npm run summarize
npm run site-map
npm run request-examples
npm run sanitize
npm run sensitive-check
```

`npm run request-examples` 只输出本地参数样例；不会访问正式系统。

`npm run api-manifest` 会从覆盖矩阵生成 [docs/api.manifest.generated.json](docs/api.manifest.generated.json)。

`npm run api-requests` 会从 manifest 和本地请求构造器生成 [docs/api.requests.generated.json](docs/api.requests.generated.json)；`npm test` 会检查该文件是否过期。

`npm run site-map` 会扫描 [static-snapshot/bksxk.nwafu.edu.cn/xsxkapp/static](static-snapshot/bksxk.nwafu.edu.cn/xsxkapp/static) 里的业务脚本，解析 `BH_UTILS` 和 jQuery AJAX 调用，生成 [docs/site-map.generated.md](docs/site-map.generated.md) 和 [docs/site-map.generated.json](docs/site-map.generated.json)。

`npm run static-assets` 会从 [static-snapshot](static-snapshot) 生成 [docs/static-assets.manifest.generated.json](docs/static-assets.manifest.generated.json)，记录 79 个持久化静态文件的大小、SHA-256 和来源 URL；`npm test` 会离线校验这些文件没有丢失、被改动或缺少登录加密依赖。

`npm run offline-snapshots` 会从本机 `artifacts/latest/snapshot/dom.html` 生成 [snapshots/grablessons.sanitized.html](snapshots/grablessons.sanitized.html)，并在存在 `BKSXK_LOGIN_HTML` 或 `/tmp/bksxk-index.html` 时刷新 [snapshots/index.sanitized.html](snapshots/index.sanitized.html)，同时生成 [docs/offline-snapshots.manifest.generated.json](docs/offline-snapshots.manifest.generated.json)。生成结果脱敏、禁用脚本执行，并把页面资源改为本地 `static-snapshot/`；`npm test` 的检查模式不依赖 `artifacts/` 或网络。

`npm run page-manifest` 会从 [docs/site-map.generated.json](docs/site-map.generated.json) 生成 [docs/page.manifest.generated.json](docs/page.manifest.generated.json)，覆盖 `*default/*.do` 页面和 `./selectedcourse.do` 等片段入口。

`npm run response-schemas` 会从 manifest、运行期摘要和人工笔记生成 [docs/api.response-schemas.generated.json](docs/api.response-schemas.generated.json)；写操作响应不会伪造，只标记为未执行。

`npm run client-contract` 会把 manifest、请求样例、响应字段和页面入口合成 [docs/client.contract.generated.json](docs/client.contract.generated.json)，并严格校验各生成物的 `id/method/endpoint` 等字段一致。

`npm run go-catalog` 会从 [docs/client.contract.generated.json](docs/client.contract.generated.json) 和端点审计生成 [docs/go-client-catalog.generated.md](docs/go-client-catalog.generated.md)，把表单内 JSON 字段也展开成路径，便于写 Go struct、构造器和覆盖测试。

`npm run coverage-check` 会把 [docs/site-map.generated.md](docs/site-map.generated.md) 的 API 入口和 [docs/api.coverage.md](docs/api.coverage.md) 对齐，按 `METHOD + endpoint` 检查有方法的调用，并要求静态裸 URL 引用也能在覆盖矩阵中找到对应接口。

`npm run endpoint-audit` 会生成 [docs/endpoint-inventory.audit.generated.md](docs/endpoint-inventory.audit.generated.md) 和 [docs/endpoint-inventory.audit.generated.json](docs/endpoint-inventory.audit.generated.json)，核对 `static-snapshot/` 字面量 `.do` 引用、`docs/site-map.generated.json` 重建出的 AJAX 调用、运行期 `artifacts/latest/network.jsonl` 请求、覆盖矩阵和 [docs/client.contract.generated.json](docs/client.contract.generated.json) 是否一致。

`npm run sensitive-check` 会扫描准备提交的文档、脚本和生成物，拦截真实 token、账号、验证码、密码、学生号路径等敏感值；`artifacts/` 仍由 `npm run sanitize` 单独清洗且不进入 git。

## 仓库结构

```text
.
├── docs/                         # API 笔记、自动摘要、站点地图
├── scripts/                      # 摘要、清洗、请求构造、采集辅助脚本
├── snapshots/                    # 脱敏离线页面快照
├── static-snapshot/              # 可提交静态资源和业务脚本快照
├── userscripts/                  # 浏览器内请求记录与写操作阻断脚本
├── extensions/bksxk-guard/       # 本地 Chromium 扩展壳
├── artifacts/                    # 本地快照和接口日志，忽略提交
├── package.json
└── README.md
```

## 操作约束

研究添加课程、退选、教材订退等写操作时，只整理字段、调用链和本地 mock 参数，不为了获取响应去改变正式系统里的真实选课状态。
