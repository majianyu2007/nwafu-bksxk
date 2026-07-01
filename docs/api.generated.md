# BKSXK API 捕获摘要

生成时间：2026-07-01T01:37:17.603Z

来源日志：`artifacts/latest/network.jsonl`

> 这份文档只保留接口结构、字段形状和本地阻断状态；Cookie、Token、密码、学号等敏感值应只留在本地 artifacts 中，且不要提交。 

## 接口列表

| 方法与路径 | 次数 | 资源类型 | Query Keys | Body Shape | 本地阻断 |
| --- | ---: | --- | --- | --- | ---: |
| `GET https://bksxk.nwafu.edu.cn/` | 1 | xhr | timetemp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/elective/batch.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/elective/courseResult.do` | 2 | xhr | timestamp, studentCode, electiveBatchCode | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/elective/unsuccessful.do` | 1 | xhr | isRead, studentCode, electiveBatchCode | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo.do` | 1 | xhr | timestamp, pageSize, pageNumber | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo/celebrityfamous.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo/dictionary.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo/fx/nj.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo/fx/yx.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo/onlineUsers.do` | 2 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo/sysparam.do` | 1 | xhr | timestamp, _ | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo/zx/nj.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/publicinfo/zx/yx.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/<redacted>.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/4/vcode.do` | 1 | xhr | timestamp | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/check/login.do` | 1 | xhr | timestrap, loginName, loginPwd, verifyCode, vtoken | `"-"` | 0 |
| `GET https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/guideMap.do` | 1 | xhr | timestamp, studentCode | `"-"` | 0 |
| `POST https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/elective/recommendedCourse.do` | 1 | xhr | - | `{"querySetting":"string"}` | 0 |
| `POST https://bksxk.nwafu.edu.cn/xsxkapp/sys/xsxkapp/student/xkxf.do` | 1 | xhr | - | `{"xh":"string","xklcdm":"string","xklclx":"string"}` | 1 |

## 本地阻断的写操作请求

本次日志中没有本地阻断的选课/退选写操作请求。
