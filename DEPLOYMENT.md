# 构建与发布

选课系统需要校园网（校外用学校 VPN）。学校凭据不会附加到 GitHub 或
`mjy.js.org` 更新检查；主动设置的 OCR 服务会接收验证码图片。

## 工具链与验证

使用 Flutter **3.44.6 / Dart 3.12.x**，最低约束已与当前锁定依赖对齐为
Flutter 3.44 / Dart 3.12。不要按旧文档的 Flutter 3.19 安装。

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
python3 -m unittest discover -s tool -p 'test_*.py'
```

各架构与能力限制见 [PLATFORMS.md](PLATFORMS.md)。以下命令都是构建方式，
不是已经通过真机验证的声明。仓库已提交各平台脚手架，不必重新 `flutter create .`。

## Android：拆 ABI 与长期签名

```bash
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64
flutter build appbundle --release --target-platform android-arm,android-arm64,android-x64
```

APK 输出在 `build/app/outputs/flutter-apk/`，分别为 `app-armeabi-v7a-release.apk`、
`app-arm64-v8a-release.apk`、`app-x86_64-release.apk`。手机通常选 arm64-v8a；
需要通用包时可自行执行不含 `--split-per-abi` 的构建命令。AAB 供商店分发，不能直接安装。

拆包去掉不属于本机的 Flutter/ONNX 原生库；所有包仍含约 13 MiB 的 OCR 模型和
约 4.4 MiB 的中文字库。保留离线识别，不以删除模型冒充优化。CI 输出实际包体积；
在真实构建前不承诺压缩比例。R8 和资源收缩已显式开启，ONNX JNI 保留规则不可删除。

本地在 `android/key.properties` 填写（文件与密钥均被忽略）：

```properties
storeFile=release.jks
storePassword=你的密钥库密码
keyAlias=你的别名
keyPassword=你的密钥密码
```

路径相对 `android/`。发布必须使用一份长期保存的密钥；不要每次重新生成。
未配置时仅本地/非 tag 预览允许 debug 签名。CI tag 发布要求四个仓库 Secrets：
`ANDROID_KEYSTORE_BASE64`、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD`、
`ANDROID_KEY_ALIAS`；缺失或不完整会失败，不会静默发布临时签名包。

旧版本使用 debug 证书，新证书可能无法覆盖安装。先备份需要的配置，确认迁移方式；
不要直接指导用户卸载导致数据丢失。使用 `apksigner verify --print-certs` 比较证书。

## macOS：Intel 与 Apple Silicon

需要完整 Xcode 与 CocoaPods，最低运行系统 macOS 14（ONNX 插件要求）。
CI 固定 `macos-15` + Xcode 16.4，避免 Xcode 27 的 Intel/lipo 行为差异。

```bash
flutter build macos --release
python3 tool/verify-native.py build/macos/Build/Products/Release arm64 x86_64
```

Release 构建应为 Universal；校验扫描整个包，包含 Flutter、App、插件及 OCR 框架。
任何文件缺少 Intel 或 ARM64 切片都失败。`ARCHS=arm64` 的本地变通构建不等于通用版。
产物为 DMG，目前未做 Developer ID 签名与公证。

网络 entitlement 已配置；未签名构建的密码存储使用传统 Keychain，失败时回退为不保存密码，
不将密码写入普通偏好设置。不要添加未配套签名的 Keychain access group。

## Windows：x64 与 ARM64

需要 Visual Studio C++ 工具链。ARM64 还需 ARM64 C++ 编译器和 ATL。

```bash
flutter build windows --release --target-platform windows-x64
flutter build windows --release --target-platform windows-arm64
python tool/verify-native.py build/windows/arm64/runner/Release arm64
```

`windows/onnxruntime.cmake` 为目标架构下载桌面 ONNX Runtime 1.22.0，通过插件的
system-library 接口接入，并显式打包 DLL。这修复了上游插件把 64 位 ARM 当成 x64 的判断。
不是把 x64 包重命名成 ARM64。发布 ZIP 必须包含 Release 整个目录。
Windows 32 位不在本次范围内。

## Linux：x64 与 ARM64

构建基线 Ubuntu 22.04；安装 `clang cmake ninja-build pkg-config libgtk-3-dev
liblzma-dev libsecret-1-dev libayatana-appindicator3-dev`。ARM64 在原生 ARM runner 上
从固定 Flutter tag 引导 SDK，不请求不存在的官方 Linux ARM64 SDK 压缩包。

```bash
flutter build linux --release --target-platform linux-x64
# 在 ARM64 构建机执行：
flutter build linux --release --target-platform linux-arm64
```

打包整个 `build/linux/<arch>/release/bundle/`；使用 `tool/verify-native.py` 检查 ELF 架构。
运行时需要 GTK 3、libsecret 和 Ayatana AppIndicator；不同发行版包名可能不同。

## iOS / iPadOS

最低 iOS 16，需完整 Xcode。CI 使用 `flutter build ios --release --no-codesign`，
把 `Runner.app` 放入 `Payload/` 后生成名称含 `unsigned` 的 IPA。
**未签名 IPA 不能直接安装**，需维护者/用户配置 Apple 签名和描述文件；商店/TestFlight
上架还需单独配置。已有 Apple 开发环境可使用 `flutter build ipa` 自行导出签名包。
iOS 不承诺持续后台抢课；请保持应用前台。

## 原生鸿蒙

不使用 ArkWeb 套壳，不把 APK 改名成 HAP。当前未完成 Flutter 原生移植，
SDK/Dart 版本差距及原生插件移植表见 [docs/HARMONYOS.md](docs/HARMONYOS.md)。
因此主发布流水线不会产生或宣传 HAP；支持 APK 的鸿蒙设备另按 Android 兼容情况判断。

## Web 与下载页

```bash
flutter build web --release --base-href /nwafu-bksxk/app/ --no-web-resources-cdn
```

流水线把 `site/` 放在站点根目录、`build/web/` 放在 `app/`、桥接脚本放在根目录。
Pages 选择 `web` 分支根目录，应用地址为 `https://mjy.js.org/nwafu-bksxk/app/`。
仅 main 分支构建会部署网站，PR、tag 和其他分支的手动构建不覆盖线上站点。
不要在源码工作区使用旧文档的 `rm -rf *` 切孤儿分支部署。

使用者安装 Tampermonkey/ScriptCat 和 `bksxk-web-bridge.user.js` 后刷新页面。
脚本的 `@match` 必须覆盖托管域名，`@connect` 仅允许学校选课主机；更换服务器
不会自动扩大脚本权限。页面关闭不能继续监控，隐藏页面也可能被浏览器限速。
中文字库、OCR 模型和 WASM 本地托管，更新检查仍会访问前述更新源。

## CI 触发规则

- main 推送：分析、测试、Web 构建和部署。
- PR / 手动触发：分析、测试、Web 及全部已列出的原生构建；不发布、不部署生产站点。
- `v*` tag：必须和 `pubspec.yaml` 版本一致，所有任务成功才汇总产物、生成 SHA256SUMS
  和 Release 草稿。维护者完成平台验收后再发布草稿。
- PR/手动构建没有 Android 签名时产物标为 `debug-signed`；tag 严禁此回退。

更新版本号后再创建对应 tag，禁止覆盖已发布 tag。配置签名不等于验证了设备安装；
完整验收记录见平台说明。任何尚未完成的构建应保持“待验证”，不要写成“全部平台通过”。
