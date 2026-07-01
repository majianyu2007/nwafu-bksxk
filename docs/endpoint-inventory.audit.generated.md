# BKSXK 端点库存审计

这份报告核对持久化静态快照、运行期网络日志、覆盖矩阵和 Go 客户端合同之间的端点一致性。

## 范围

- `static-snapshot/` 下所有文本资源都会扫描字面量 `.do` 引用。
- `docs/site-map.generated.json` 提供从业务脚本重建出的 `BH_UTILS` / jQuery AJAX 调用和页面入口。
- `artifacts/latest/network.jsonl` 存在时会核对运行期请求是否进入覆盖矩阵。
- 添加选课、退选、教材订退、确认、退出等状态变更接口只验证前端调用链和本地构造，不执行真实提交。

## 统计

| 项目 | 值 |
| --- | --- |
| `apiManifestEndpoints` | `58` |
| `pageManifestEntries` | `17` |
| `clientContractEndpoints` | `58` |
| `clientContractPages` | `17` |
| `siteMapApiRows` | `56` |
| `siteMapPageRows` | `17` |
| `siteMapFunctionRows` | `327` |
| `staticAssetFiles` | `79` |
| `staticLiteralEndpoints` | `63` |
| `runtimeRequestIdentities` | `18` |
| `stateChangingEndpoints` | `10` |
| `byEndpointStatus` | `{"运行期已验证":42,"静态已定位":4,"写操作未执行":10,"静态残留":2}` |
| `byResponseAvailability` | `{"runtime-field-summary":41,"static-only":3,"binary":1,"write-not-executed":10,"static-residual-nonjson":1,"static-residual-404":1,"binary-or-empty":1}` |

## 审计结果

当前审计通过：未发现静态快照、运行期日志、覆盖矩阵和客户端合同之间的端点缺口。

### 静态字面量未覆盖

_None._

### 站点地图 API 未覆盖

_None._

### 站点地图页面未覆盖

_None._

### 运行期请求未覆盖

_None._

### 状态变更标记异常

_None._

### 客户端合同不一致

_None._

