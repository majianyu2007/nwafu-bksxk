# BKSXK API 覆盖矩阵

状态说明：

- `运行期已验证`：在登录态页面内以只读方式调用过，已记录响应字段或摘要。
- `静态已定位`：从前端脚本确认调用点和参数构造，但当前没有完整运行期样例。
- `静态残留`：脚本里有函数或字符串，但当前部署/当前流程不可用，已记录验证结果。
- `写操作未执行`：会改变选课、教材、确认、登录状态；只整理参数，不为获取响应提交。
- `待复现`：静态源码存在，但当前朴素参数未拿到有效业务响应。

## 登录与初始化

| 状态 | 方法 | 接口 | 说明 |
| --- | --- | --- | --- |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/batch.do` | 登录态可见轮次列表 |
| 运行期已验证 | POST | `/sys/xsxkapp/elective/batchisopen.do` | 轮次开放状态，`xklcdm=<batchCode>` |
| 静态已定位 | GET | `/sys/xsxkapp/student/4/vcode.do` | 验证码 token |
| 静态已定位 | GET | `/sys/xsxkapp/student/vcode/image.do` | 验证码图片 |
| 静态已定位 | GET | `/sys/xsxkapp/student/check/login.do` | 登录校验 |
| 运行期已验证 | GET | `/sys/xsxkapp/student/<studentCode>.do` | 学生信息 |
| 写操作未执行 | POST | `/sys/xsxkapp/student/xklcqr.do` | 选课轮次须知确认 |
| 运行期已验证 | GET | `/sys/xsxkapp/student/guideMap.do` | 引导页读取状态 |
| 写操作未执行 | POST | `/sys/xsxkapp/student/guideMap.do` | 标记引导页已读 |
| 写操作未执行 | GET | `/sys/xsxkapp/student/register.do` | CAS/统一身份注册 |
| 写操作未执行 | GET | `/sys/xsxkapp/student/logout.do` | 退出登录 |
| 写操作未执行 | GET | `/sys/xsxkapp/student/authlogout.do` | 认证退出 |

## 公共信息与字典

| 状态 | 方法 | 接口 | 说明 |
| --- | --- | --- | --- |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo.do` | 首页聚合信息 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/dictionary.do` | 字典 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/sysparam.do` | 系统参数 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/onlineUsers.do` | 在线人数 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/volunteer.do` | 志愿等级字典 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/fx/nj.do` | 辅修筛选年级 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/fx/yx.do` | 辅修筛选院系 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/fx/zy.do` | 辅修筛选专业 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/zx/nj.do` | 跨年级/方案外筛选年级 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/zx/yx.do` | 跨年级/方案外筛选院系 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/zx/zy.do` | 跨年级/方案外筛选专业 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/notice.do` | 公告列表 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/notice/view.do` | 公告详情 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/problem.do` | 常见问题 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/celebrityfamous.do` | 页脚/名言信息 |

## 课程列表与查询

| 状态 | 方法 | 接口 | 说明 |
| --- | --- | --- | --- |
| 运行期已验证 | POST | `/sys/xsxkapp/elective/recommendedCourse.do` | 推荐课程，课程行含 `tcList` |
| 运行期已验证 | POST | `/sys/xsxkapp/elective/programCourse.do` | 方案内、方案外、重修、体育、辅修等入口 |
| 运行期已验证 | POST | `/sys/xsxkapp/elective/publicCourse.do` | 公选课程入口 |
| 运行期已验证 | POST | `/sys/xsxkapp/elective/queryCourse.do` | 全校课程，返回教学班平铺行 |
| 运行期已验证 | POST | `/sys/xsxkapp/elective/testCourse.do` | 实验课查询 |
| 运行期已验证 | POST | `/sys/xsxkapp/elective/course/kcssfa.do` | 课程所属方案 |
| 静态残留 | GET | `/sys/xsxkapp/elective/course.do` | 静态 `queryCourse()` 封装；运行期 GET 不返回业务 JSON，业务查询用 POST |
| 运行期已验证 | POST | `/sys/xsxkapp/elective/course.do` | 侧边栏课程搜索；静态封装写 GET，但业务 JSON 实测为 POST |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/course/volunteer.do` | 课程可选志愿等级，参数为 `queryParam={"data":...}` |
| 静态残留 | GET | `/sys/xsxkapp/elective/volunteered.do` | 当前部署返回 404；已选志愿弹窗实际走 `courseResult.do` |

## 已选、课表与详情

| 状态 | 方法 | 接口 | 说明 |
| --- | --- | --- | --- |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/courseResult.do` | 已选课程 |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/returnResults.do` | 退选日志 |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/unsuccessful.do` | 落选课程 |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/queryStudentQueue.do` | 队列信息 |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/teachingTime.do` | 已排课表 |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/noArranged.do` | 未安排时间课程 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/queryjxb.do` | 教学班详情 |
| 运行期已验证 | GET | `/sys/xsxkapp/elective/teachingclass/capacity.do` | 教学班容量 |
| 运行期已验证 | GET | `/sys/xsxkapp/util/canchoose.do` | 可选原因分析 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/querykcxx.do` | 课程详情 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/queryjzg.do` | 教师详情 |
| 运行期已验证 | GET | `/sys/xsxkapp/publicinfo/queryjzgphoto.do` | 教师照片 |
| 运行期已验证 | POST | `/sys/xsxkapp/student/xkxf.do` | 选课学分信息 |
| 运行期已验证 | POST | `/sys/xsxkapp/student/xscj.do` | 成绩详情，本次菜单未开放 |
| 运行期已验证 | POST | `/sys/xsxkapp/textbook/queryxsjxbbook.do` | 教材查询 |

## 状态变更

| 状态 | 方法 | 接口 | 说明 |
| --- | --- | --- | --- |
| 写操作未执行 | POST | `/sys/xsxkapp/elective/volunteer.do` | 添加选课，表单字段 `addParam` |
| 写操作未执行 | GET | `/sys/xsxkapp/elective/deleteVolunteer.do` | 退选，表单/查询字段 `deleteParam` |
| 静态已定位 | POST | `/sys/xsxkapp/elective/studentstatus.do` | 选课/退选处理状态轮询 |
| 写操作未执行 | POST | `/sys/xsxkapp/textbook/addbook.do` | 订购教材 |
| 写操作未执行 | POST | `/sys/xsxkapp/textbook/modifybook.do` | 修改/退订教材 |
| 写操作未执行 | GET | `/sys/xsxkapp/elective/submit/unsuccessful.do` | 落选提醒确认 |
