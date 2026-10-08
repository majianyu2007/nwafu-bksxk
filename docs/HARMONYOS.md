# HarmonyOS 原生移植状态

**尚未实现，不提供 HAP。维护者已选择坚持 Flutter 原生，不接受 ArkWeb 套壳。**
这份记录列出实际阻塞项，不把增加一个目录或 CI 任务当成“支持鸿蒙”。

## 两类系统不能混称

- 本身允许安装 APK 的鸿蒙设备：可尝试对应 ABI 的 Android 包，需要设备验收。
- 原生 HarmonyOS NEXT / 5 及后续系统：需要真正的 OHOS/HarmonyOS 工程、引擎、
  插件和签名。APK、AAB、ARM64 Windows/Linux 二进制都不能代替 HAP。
- 也不宣称支持手表、车机、电视等所有设备形态；需按目标 SDK 与设备能力分别验收。

## SDK 版本阻塞

2026-10-08 检查维护方仓库，公开主线为 `oh-3.35.7-release`，发布说明包含
3.35.7+ohos-1.0.5。本项目锁定 Flutter 3.44.6，依赖要求 Dart >=3.12 / Flutter >=3.44。
因此不能在现有锁文件上直接换成该 SDK，也不能仅降低 pubspec 的版本声明冒充兼容。

维护方来源（Gitee 旧入口已迁移）：

- [CPF-Flutter/flutter_flutter](https://gitcode.com/CPF-Flutter/flutter_flutter)
- [CPF-Flutter/flutter_packages](https://gitcode.com/CPF-Flutter/flutter_packages)
- [Flutter 官方支持平台](https://docs.flutter.dev/reference/supported-platforms)

先在独立移植分支选择可维护的 OHOS SDK 固定版本，解决 Dart/Flutter API 与锁文件
兼容性；不能为了 HAP 破坏主线桌面和 Android 已有行为。现有环境没有 DevEco SDK、
HarmonyOS 签名材料及设备，不能完成真实 HAP 构建/安装验收。

## 插件与本机能力清单

下表是**本项目使用方式的移植要求**，不是断言社区不存在相关替代插件。
替代实现必须记录源仓库、固定提交、许可和验收结果，不能只依赖名称相似。

| 依赖/模块 | 必须完成的适配与验收 |
| --- | --- |
| `flutter_onnxruntime` 1.8.0 | 当前包列出 Android/iOS/macOS/Windows/Linux/Web，没有本项目可用的 OHOS 实现；移植原生推理、模型加载、int64/CTC 输出与内存释放，保持现有模型/字表契约 |
| `flutter_secure_storage` | 使用鸿蒙安全存储实现；跨重启、升级、删除账号后验收；不得退化为明文密码 |
| `shared_preferences` / `path_provider` | 对应 OHOS 插件接入、账号/课程缓存持久化，验证升级不丢数据 |
| `flutter_local_notifications` | 通知初始化、权限、选课结果与点击路由；不能把无实现的 no-op 标成可用 |
| `flutter_foreground_task` / `background_io.dart` | Android 前台服务不可照搬；实现符合鸿蒙后台规则的生命周期，验证退到后台后的轮询与会话存活 |
| `wakelock_plus` | 鸿蒙屏幕保持唤醒能力和权限，停止监控后释放；不能承诺永久后台存活 |
| `package_info_plus` / `url_launcher` | 原生版本号、构建号与外部链接，确保更新提示与 HAP 一致 |
| `dynamic_color` | 检查可用性；不可用时保留已有静态主题回退 |
| `window_manager` / `tray_manager` | 手机端不启用桌面托盘，验证平台条件分支与插件注册不会误用 Android 实现 |
| 网络 / 登录 / 加解密 | 验证 OHOS 的 TLS、Cookie、token、超时和请求取消；继续使用离线请求向量测试 |

## 完成顺序与发布门槛

1. 选定 SDK 与设备最低版本，原生 Flutter 空工程在真机运行；记录固定引擎提交。
2. 在独立分支重新解出兼容依赖，迁移上述插件，跑现有离线单测与界面测试。
3. 先打通登录、验证码、查询、缓存和安全存储，再补齐通知/后台能力。发现缺失能力必须在 UI 明示。
4. 使用 DevEco 工具链创建正式 `ohos/` 工程，配置应用身份、设备类型、权限与签名；私钥不入库。
5. 构建与检查原生 HAP，真机验收冷启动、OCR、登录/重登录、查询、账号切换、通知、后台生命周期和升级。
6. 上述门槛达成后，才把 HAP 任务加入主 release 的必需任务列表和下载页。

本次未添加一个必然失败/不完整的 HAP 发布任务，也未生成空壳包。
