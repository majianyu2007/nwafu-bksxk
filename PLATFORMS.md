# 平台与架构

以下是构建目标，**不表示所有目标已经通过真机测试**。以对应提交的 GitHub
Actions 结果、Release 附件和发布前验收记录为准。新增流水线尚需首次完整执行。

| 平台 | 架构与产物 | 运行要求 / 状态 |
| --- | --- | --- |
| Android | `android-arm64-v8a.apk` | 常见 ARM64 手机首选；包含本机 OCR |
| Android | `android-armeabi-v7a.apk` | ARM32 设备；需确认设备系统满足 Flutter/插件最低版本 |
| Android | `android-x86_64.apk` | x64 设备/模拟器；不是 ARM 手机包 |
| Android 商店 | `android.aab` | 分发系统按设备拆包，不能直接侧载 |
| Windows | `windows-x64.zip` | Windows 10/11 x64；解压整个目录后运行 |
| Windows | `windows-arm64.zip` | 原生 ARM64；OCR 使用 ARM64 运行库，CI 校验所有 PE 文件 |
| macOS | `macos-universal.dmg` | macOS 14+；每个 Mach-O 同时含 arm64 和 x86_64，含插件与 OCR 框架 |
| Linux | `linux-x64.tar.gz` / `linux-arm64.tar.gz` | Ubuntu 22.04 构建基线；需要 GTK 3、libsecret、Ayatana AppIndicator |
| iOS / iPadOS | `ios-arm64-unsigned.ipa` | iOS 16+；必须另行签名，未提供 App Store/TestFlight 分发 |
| Web | `web-site.tar.gz` | 现代浏览器、校园网、配套桥接脚本；归档按 `/nwafu-bksxk/` 部署 |
| 鸿蒙 APK 兼容设备 | 对应 Android APK | 仅适用于设备本身仍支持 APK 的情况；未做鸿蒙真机验收 |
| 原生 HarmonyOS | 暂无 HAP | 坚持 Flutter 原生路线；见 [移植阻塞项](docs/HARMONYOS.md) |
| Windows 32 位 | 不提供 | 根据项目维护者要求不纳入本次目标 |

文件名均带 `nwafu-bksxk-` 前缀。未配置正式 Android 签名的 PR/手动预览包
另带 `-debug-signed`，仅供测试，不保证能覆盖安装既有版本。

## 能力区别

| 能力 | 桌面原生 | Android | iOS | Web |
| --- | --- | --- | --- | --- |
| 选课 / 查询 / 本地目录 | 支持 | 支持 | 支持 | 需桥接脚本 |
| 本地 OCR | 原生 ONNX | 原生 ONNX | 原生 ONNX | WASM ONNX |
| 关闭窗口后监控 | 可缩到可用托盘 | 前台服务，仍受系统限制 | 不保证，需前台 | 不支持 |
| 通知 | 依权限/桌面环境 | 依权限 | 依权限 | 依浏览器权限与页面存活 |
| 安全保存密码 | 平台密钥存储 | 平台密钥存储 | Keychain | 浏览器存储实现，不等同原生钥匙串 |

## 发布验收

- CI：分析与离线测试、每个目标编译、APK ABI/JNI 检查、桌面/IPA 架构检查。
- 真机：冷启动、OCR 与手工验证码、登录/重新登录、查询与切换账号、320px/大字体、托盘恢复、通知和实际后台行为。
- CI 不连接学校服务器，也不执行真实选课/退课。带写操作的验收由维护者明确选择测试账号和课程后执行。
- APK 必须用同一份长期密钥签名。macOS 包尚未 Developer ID 签名/公证；iOS IPA 未签名，均不能宣传为已完成商店分发。
- 成功构建后才产生 Release 草稿；完成验收再公开发布。缺失密钥、架构不匹配或任一必需任务失败都会阻止生成正式产物集合。
