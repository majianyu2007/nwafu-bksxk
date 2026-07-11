# 部署与构建指南 · Deployment Guide

本文档说明如何构建、运行和部署「西农本科选课」客户端。核心原则：**除加载页面资源外，程序只与 `https://bksxk.nwafu.edu.cn` 通信**，且该系统仅在校园网内可用（校外需 VPN 接入校园网）。

## 目录

- [环境要求](#环境要求)
- [通用步骤](#通用步骤)
- [macOS 原生应用](#macos-原生应用)
- [Windows / Linux 桌面](#windows--linux-桌面)
- [Android / iOS](#android--ios)
- [Web 网页版（静态部署 + 跨域桥接脚本）](#web-网页版静态部署--跨域桥接脚本)
- [字体与离线性](#字体与离线性)

---

## 环境要求

- Flutter stable ≥ 3.19（开发使用 3.44.6 / Dart 3.12.2 验证）。
- 各目标平台的原生工具链见下文分节。

```bash
# (仓库根目录就是 Flutter 工程)
flutter pub get
flutter analyze      # 应为 No issues found
flutter test         # 30 个测试全部通过
```

---

## 通用步骤

所有平台共用同一套 Dart 代码。构建前先 `flutter pub get`。若切换过分支或改过包名，遇到奇怪的缓存报错时先 `flutter clean` 再 `flutter pub get`。

---

## macOS 原生应用

> **前置条件：必须安装完整版 Xcode**（App Store 安装），仅有 Command Line Tools 无法编译 macOS/iOS —— 会报 `xcrun: error: unable to find utility "xcodebuild"`。

安装完整 Xcode 后一次性配置：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

然后构建 / 运行：

```bash
# (仓库根目录就是 Flutter 工程)
flutter run -d macos          # 调试运行
flutter build macos           # Release 产物: build/macos/Build/Products/Release/西农本科选课.app
```

已为你配置好的 macOS 工程要点：

- **沙盒网络权限**：`macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements` 均已加入 `com.apple.security.network.client`。缺少它时沙盒会静默拦截所有出站请求，应用连不上服务器。
- Bundle 标识：`cn.edu.nwafu.nwafuBksxk`；显示名：西农本科选课；最低系统 macOS 10.15。
- 通知：`flutter_local_notifications` 走系统通知中心，首次登录后申请权限。

---

## Windows / Linux 桌面

```bash
# Windows（需 Visual Studio + Desktop C++ 工作负载）
flutter build windows

# Linux（需 clang / cmake / ninja / GTK 开发库）
flutter build linux
```

窗口标题与 Android 标签均为「西农本科选课」。

---

## Android / iOS

```bash
# Android（需 Android SDK）
flutter build apk --release          # 或 appbundle

# iOS（需完整 Xcode，同 macOS 前置条件）
flutter build ipa
```

已配置：

- **Android**：`INTERNET` 权限已放入 **主** manifest（`android/app/src/main/AndroidManifest.xml`），并加入 `POST_NOTIFICATIONS`（Android 13+ 运行时通知权限）。注意 Flutter 默认只在 debug/profile manifest 里加 `INTERNET`，release 必须在主 manifest 显式声明，否则联网失败——本项目已处理。
- **iOS**：显示名西农本科选课。

---

## Web 网页版（静态部署 + 跨域桥接脚本）

学校后端不返回 CORS 头，浏览器**直连会被拦截**，且浏览器禁止页面 JS 设置 `Cookie`/`User-Agent`。因此网页版需要一个配套的浏览器脚本来桥接。整套方案是**纯静态**的，可部署到 GitHub Pages 等。

### 1. 构建静态站点

```bash
# (仓库根目录就是 Flutter 工程)
flutter create . --platforms web --project-name nwafu_bksxk   # 首次生成 web/ 脚手架
flutter build web --release
# 产物在 build/web/，是纯静态文件
```

### 2. 部署到 web 分支 / 静态托管

把 `build/web/` 的内容发布到任意静态托管（GitHub Pages、Cloudflare Pages、Vercel、Netlify 或校内静态服务器）。例如用 `web` 分支托管 GitHub Pages：

```bash
# 在仓库根目录
git switch --orphan web
rm -rf *                       # 清空工作区（web 分支只放构建产物）
cp -r build/web/* .
git add .
git commit -m "Publish web build"
git push -u origin web
# 然后在 GitHub 仓库 Settings → Pages 选择 web 分支根目录
```

> 该 Flutter 应用是**静态**的（无服务端逻辑），因此适合 web 分支静态托管。它不需要任何后端服务器；所有业务请求由用户浏览器直接发往校园网选课服务器。

### 3. 安装跨域桥接脚本

网页首次打开会弹窗提示安装脚本。用户需：

1. 安装 **篡改猴 (Tampermonkey)** 或 **脚本猫 (ScriptCat)** 浏览器扩展；
2. 安装本仓库的 [`userscripts/bksxk-web-bridge.user.js`](../userscripts/bksxk-web-bridge.user.js)（在 Tampermonkey 中新建脚本粘贴，或从托管地址导入）；
3. **确认脚本的 `@match` 覆盖你的部署域名**（脚本默认匹配 `localhost`、`*.github.io`、`*.pages.dev`、`*.vercel.app`、`*.netlify.app`；自定义域名需自行添加一条 `@match`）；
4. 刷新页面。

脚本原理：它把 `window.XMLHttpRequest` 替换为一个转发器——发往 `bksxk.nwafu.edu.cn` 的请求改走 `GM_xmlhttpRequest`（不受 CORS 限制、自动携带浏览器里的选课站 Cookie、可设置被禁止的请求头），其余请求（字体、同源资源等）仍走原生 XHR。安装后应用无需改动即可工作。`@connect` 仅限 `bksxk.nwafu.edu.cn`，脚本只能访问选课主机。

安装后应用检测到 `window.__bksxkBridgeReady` 便不再弹提示。

### Web 限制说明

- 仍然只能在**校园网**内使用（脚本绕过的是 CORS，不是网络可达性）。
- 系统通知在 web 上不可用（原生端可用）。
- 安全存储在 web 上退化为浏览器本地存储，隐私性弱于桌面/移动端的系统钥匙串；对凭据敏感的用户建议使用原生端。

---

## 字体与离线性

应用打包了 **Noto Sans SC 的 GB2312/GBK 子集**（OFL 1.1，见 `assets/fonts/OFL_NOTICE.txt`），因此：

- 中文（含任意课程名/教师名）离线即可正确显示；
- **运行时不访问任何字体 CDN**，符合「只连接 bksxk.nwafu.edu.cn」的要求。

若需覆盖更多生僻字，可用 `fonttools` 的 `pyftsubset` 扩大子集字符集后替换 `assets/fonts/` 下的两个 ttf（Regular/Medium）。
