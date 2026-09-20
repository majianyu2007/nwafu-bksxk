# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A cross-platform Flutter client (`nwafu_bksxk`, display name 西农本科选课) for the NWAFU undergraduate course-selection system at `https://bksxk.nwafu.edu.cn`. Its purpose is to select and auto-grab courses faster than the official web UI. The repo root **is** the Flutter project.

Two branches by design:
- **`main`** — the app (this tree). `flutter run` works from the root.
- **`api`** — the original reverse-engineering research (`docs/api.notes.md`, `docs/api.runtime.md`, `static-snapshot/`, `scripts/request-builders.mjs`). Code comments here cite those docs; read them with `git show api:docs/api.notes.md`. Do not merge `api` into `main`.
- `web` is a deploy-only orphan branch written by CI (GitHub Pages); never commit to it by hand.

The backend is reachable **only on the campus network**. Off-campus, the app shows the campus-network hint and every request fails with `AppErrorKind.campusNetwork` — that is expected, not a bug. `flutter run --dart-define=BKSXK_API_ORIGIN=http://localhost:PORT` pins the origin to a local simulator and locks the Settings origin field (see `Storage.originLockedByBuild`). The `testserver` branch (checked out as a worktree at `../nwafu-bksxk-testserver`) adds `tool/testserver.dart`, a stateful local selection server, plus `test/testserver_e2e_test.dart`; neither exists on `main`.

## Commands

Flutter is at `/opt/homebrew/bin/flutter` (3.44.6 / Dart 3.12.2). No codegen (no build_runner): providers are hand-written.

```bash
flutter pub get
flutter analyze                                   # must be clean (lints in analysis_options.yaml)
flutter test                                      # ~90 tests, no network needed
flutter test test/monitor_engine_test.dart        # one file
flutter test --plain-name "double-fired"          # one test by name substring
flutter run -d macos                              # or android / ios / windows / linux / chrome
```

Builds:

```bash
flutter build apk --release
flutter build windows / linux
# macOS needs full Xcode; if only Xcode-beta is installed, set DEVELOPER_DIR instead of xcode-select:
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer flutter build macos
tool/create-dmg.sh                                # packages build/macos/.../Release/西农本科选课.app into a DMG
flutter build web --release --base-href /nwafu-bksxk/app/   # what CI runs; web/ is committed (custom index.html + web/ort/)
```

`.github/workflows/release.yml` builds all native platforms on every push to `main`, deploys the web app + `site/` landing page + userscript to the `web` branch, and publishes a GitHub Release on `v*` tags.

Gotchas:
- `flutter create . --platforms web` re-adds a stub `test/widget_test.dart`; delete it before `flutter test`.
- Under Xcode 27 beta, universal `flutter build macos --release` can fail on a `lipo` check; DEPLOYMENT.md has the direct `xcodebuild ... ARCHS=arm64` command.

## Architecture

Layers: `lib/core` (constants, error taxonomy, login cipher, web-env shim) → `lib/data` (HTTP client, services, models, param builders, monitor engine, storage, captcha) → `lib/app` (Riverpod composition root + controllers) → `lib/ui` (pages). Data-layer classes take their dependencies by constructor and never import Flutter widgets or Riverpod, which is what makes them fakeable in tests.

### Request pipeline

`ApiClient` (`lib/data/api_client.dart`) is the only thing that talks to the server. It prepends `<origin>/xsxkapp`, attaches the `token` header, keeps cookies in a `CookieJar` (skipped on web), parses every body into the `ApiResult` envelope (`{code,msg,data,dataList,totalCount}`; `ok` means `code == "1"`), and classifies transport errors into `AppError`. When a response looks like an expired session (HTML login page, 401/403, or a "登录/token/会话" message) it calls `onSessionExpired`, retries **once**, and collapses concurrent expiries into a single re-login.

`SessionManager` (`lib/data/auth_service.dart`) owns the live token, student, batches and the remembered credentials, and installs itself as that `onSessionExpired` callback. Silent re-login needs a captcha, so it depends on a `CaptchaSolver`. `loginWithRetry` is the opening-rush login loop: bad password stops, bad captcha re-fetches, everything else backs off and retries.

### Correctness anchors (verified against the real site — do not regress)

- `lib/core/crypto/des_login.dart`: `loginPwd = base64(strEnc(pw, "this", "password", "is"))`, a transliteration of the site's `des.min.js`. `test/des_login_vectors.json` was produced by running the real JS under Node; `des_login_test.dart` checks byte equality.
- `lib/data/param_builders.dart`: a port of the site's `request-builders.mjs`. JSON key order and separators are asserted literally in `param_builders_test.dart`. `resolveAddParam` is the gate for `volunteer.do`: a class with `hasTest` **must** carry `testTeachingClassID`, and `hasBook` with textbook ordering open **must** carry `needBook`; otherwise it throws `MissingSelectionError` rather than submitting a wrong struct. `CourseKind` (in `core/constants.dart`) decides `isMajor` (FXKC → "0") and whether check flags are sent (QXKC omits them).
- `lib/core/errors.dart`: every failure becomes an `AppError` with a kind, Chinese message and hint. Never surface a bare "请求失败". `isHardStop` (captcha/account/throttle/session) is what the monitor uses to decide stop-vs-retry, and `fromBusiness` classifies server messages by keyword.

### The grab hot path

Adding a course is split into **resolve** and **submit**. `resolveAddParam` builds the complete form (`AddParamPlan`) up front; `EnrollService.submitAdd` is one POST with no logic. `MonitorEngine` (`lib/data/monitor_engine.dart`) runs one timer per `Watch`, polls `capacity.do` with jitter, and on `remaining > 0` fires the pre-resolved plan. Safety rules encoded there and locked by `monitor_engine_test.dart`:
- `submitInFlight` prevents double-submitting one seat; a watch grabs at most once.
- Success is declared only after `studentstatus.do` confirms (`confirmAfterGrab`).
- Normal mode: a maintenance/throttle signal halts the **entire** engine. `rushMode` treats throttle/5xx/timeout as transient and backs off instead. Captcha/account errors always stop the watch.
- **Gate**: `closeGate()` lets watches poll without submitting; `PlanController` (`lib/app/monitor_providers.dart`) polls `batchisopen.do` and calls `openGate(grabNow: true)` the instant the batch opens.

Tests fake `CourseService`/`EnrollService` by subclassing or `implements` + `noSuchMethod`; the engine accepts an injected `Random`.

### Riverpod composition (`lib/app/providers.dart`)

`storageProvider` is overridden in `main()` with an opened `Storage`. **Several accounts can be signed in at once**, each with its own server session: `sessionScopeProvider(accountId)` (a family keyed by login name) builds one `SessionScope` = `ApiClient` (own cookies + token) → services → `SessionManager` → `MonitorEngine` with its own persisted watch list (`Storage.watchesJson(accountId)`). `sessionControllerProvider(id)` holds that account's `SessionState` and runs its 45 s heartbeat. `signedInAccountsProvider` lists signed-in ids, `activeAccountIdProvider` is the one the shell shows, and `enterAccount`/`leaveAccount` are the only ways to change either. Pages read the shown account through the `current*` views (`sessionProvider`, `courseServiceProvider`, `monitorEngineProvider`, `coursesProvider`, `watchesProvider`, …), so page code never threads ids. `selectionDataRevisionProvider(id)` is a per-account monotonic counter: bump it (`bumpSelectionRevision` / `bumpCurrentSelectionRevision`) after any enrollment mutation or batch switch so the courses/selected/credit providers refetch. `monitor_providers.dart` bridges each engine's streams to the UI; `RootShell` watches `notificationBridgeProvider(id)` for every signed-in account so notifications fire for accounts that are not on screen. Shared settings (theme, OCR API, monitor config, silent-relogin budget) stay global. `anonymousAuthProvider` / `publicInfoServiceProvider` are session-less clients for the login captcha and public endpoints. **Multi-account is off by default** (`multiAccountProvider`, Settings → 账号 → 多账号): off, a new login replaces the signed-in account; on, the shell shows browser-style `AccountTabs` and Settings/login offer 添加账号. `backgroundDriverProvider` (read by the shell) turns the platform keep-alive on while any engine runs. `courseCacheProvider` (`lib/data/course_cache.dart`) holds gzip+base64 course lists in SharedPreferences keyed per account/round/kind/query/page; `CoursesController.load` shows the cached rows first (`CoursesState.cachedAt`) and replaces them when the server answers.

### Background running (`lib/data/background*.dart`)

`AppBackground` is a conditional-import seam (web stub / `background_io.dart`). Desktop: `window_manager` + `tray_manager` 0.5 turn a window close into hide-to-tray (the tray menu has 打开窗口 / 退出; macOS uses the template icon in `assets/icons/`), `wakelock_plus` keeps the display awake while a monitor runs. Android: `flutter_foreground_task` starts a `dataSync` foreground service (manifest declares the service + `FOREGROUND_SERVICE_DATA_SYNC`) while a monitor runs, with a persistent notification, plus the battery-optimisation prompt. iOS: wakelock only (no user-startable background service; say so, do not fake it). Windows notifications need `WindowsInitializationSettings` (appUserModelId `cn.edu.nwafu.nwafuBksxk`). Settings → 后台运行 has the two switches (`runInBackgroundProvider`, `keepAwakeProvider`). Linux builds need `libayatana-appindicator3-dev` (CI installs it).

### Platform split via conditional imports

Web cannot use `dart:io`/`dart:ffi` and native must not import `dart:js_interop`, so three seams use `stub if (dart.library.X) impl` files:
- `core/web_env*.dart` — is-web + "is the CORS bridge userscript installed" checks.
- `data/captcha_solver_factory*.dart` — both sides currently return `OnnxCaptchaSolver`; on web it only works if `web/index.html` has loaded `window.ort` from `web/ort/`.
- `data/browser_notifications*.dart` — Web Notifications vs no-op; `NotificationService` wraps this plus `flutter_local_notifications`.

Keep new platform-specific code behind the same pattern; a bare `dart:io` import in shared code breaks `flutter build web`.

### Captcha OCR

The bundled model is `assets/models/autoverify.onnx` (quantized ddddocr CRNN from the AutoVerify extension, author-permitted) run through `flutter_onnxruntime`. Contract: input `[1,1,64,W]` float32 normalized to [-1,1], output int64 indices (ArgMax in-graph), CTC-collapse, charset in `autoverify_charset.json` (index 0 = blank). It is warmed up in `main()` before the login screen mounts (after the first frame on web, where it is a 14 MB download). `solve()` returns null on any failure and the UI falls back to manual entry. **Do not** switch to the float ddddocr model, the old `onnxruntime` package, or a synthetically trained model — all were tried and miscompute or underperform on the native runtime.

### Web build

The school server sends no CORS headers, so the web app only works with the Tampermonkey/ScriptCat bridge in `web_bridge/bksxk-web-bridge.user.js` (v1.1.0), which replaces `XMLHttpRequest` for the API host with `GM_xmlhttpRequest`. Dio's browser adapter sends bodies as `Uint8Array`; the bridge must decode them to a string (`normaliseBody`) or GM sends the text "[object Uint8Array]" and every POST (course queries, selection) fails while GETs (login, courseResult) work, which is exactly the "can log in but nothing else works" symptom. Test the shim without a browser with a fake `GM_xmlhttpRequest` under Node. The app detects it via `window.__bksxkBridgeReady` or the `data-bksxk-bridge-ready` DOM attribute. If you change the deployed URL, update the `@match`/`@downloadURL` lines in the userscript header. Build with `--no-web-resources-cdn` (CI does) so CanvasKit ships next to the app instead of from gstatic.com, which is slow or blocked on campus; `web/index.html` shows a boot screen until `flutter-first-frame` and loads onnxruntime-web deferred. The fonts are a GB2312 + course-catalogue subset (2.3 MB each, was 7.7 MB); regenerate with fontTools if the catalogue grows characters outside GB2312.

## Platform configuration that was hard-won

- **macOS keychain**: `Storage` uses `MacOsOptions(useDataProtectionKeyChain: false)` because the data-protection keychain needs a real code signature (errSecMissingEntitlement / -34018 on unsigned builds). All secure-storage calls are try/caught and flip `secureStorageAvailable`. Do not add a `keychain-access-groups` entitlement.
- **macOS entitlements**: `com.apple.security.network.client` must be in both `DebugProfile.entitlements` and `Release.entitlements`; without it the sandbox silently blocks all network. `macos/Runner/Info.plist` sets `NSAllowsLocalNetworking` so a `localhost` simulator origin is allowed.
- **macOS deployment target is 14.0** (required by `flutter_onnxruntime`); `macos/Podfile` forces it on every pod in `post_install`.
- **Android**: `INTERNET` and `POST_NOTIFICATIONS` live in the **main** manifest; Flutter only auto-adds `INTERNET` to debug/profile.
- **Fonts**: a Noto Sans SC subset (GB2312 plus every character in the live course catalogue, Latin, CJK punctuation) is bundled in `assets/fonts/`; the app must never contact a font CDN. The only network peer is the school server (plus a user-configured OCR API if set).
- **Windows**: `windows/runner/CMakeLists.txt` compiles with `/utf-8`; without it MSVC read the UTF-8 sources in the machine's ANSI code page and the Chinese window title came out as mojibake. `Runner.rc` uses `#pragma code_page(65001)` for the same reason.

## Safety

`volunteer.do`, `deleteVolunteer.do`, `addbook.do`, and `modifybook.do` change real enrollment state. They run only on explicit user action (drops behind a confirmation dialog) or from an armed watch the user created. Never add code paths that fire them automatically for testing; use fakes or the `testserver` branch's local simulator.

## Live-server facts (verified against bksxk.nwafu.edu.cn on 2026-09-14 and 2026-09-18, read-only)

These contradict reasonable assumptions and are locked by `test/live_payloads_test.dart`:

- **One session per account.** A new login (app, browser, curl) invalidates the previous token; the old client gets HTTP 200 with `code "302" / 未查询到登录信息` on authenticated endpoints and `code "2" / 非法请求` on `xkxf.do`, while public endpoints (`batch.do`, `notice.do`, `sysparam.do`, `dictionary.do`, `queryjxb.do`, `canchoose.do`, `batchisopen.do`, `studentstatus.do`) keep answering normally, so a request can look healthy while the session is dead. `ApiClient._looksExpired` keys on code 302 / those messages. **An idle session dies after about 12 minutes; one pinged every 45 s stays alive indefinitely** (16+ min tested), which is why every account runs a 45 s heartbeat regardless of the monitor. The silent re-login (`SessionManager.silentReloginEnabled`, default on; captcha budget `Storage.silentReloginAttempts`, default 3) handles a drop; when it gives up, `SessionManager.lastFailure` says why (验证码识别 N 次未通过 / 密码错误 / 已关闭) and `ReloginDialog` shows it. The contested-session guard (`contestedGuardEnabled`, **off by default**, window configurable in Settings) refuses a second silent re-login within the window because the account is in use elsewhere; off, the app always wins the session back. Login does not need the captcha request's cookies: the captcha is keyed by `vtoken`, so the login screen fetches captchas from a session-less client.
- **`capacitySuffix` is `""` on every class.** The parameter must still be sent (the server rejects its absence); an empty value is fine. Never skip the capacity poll because the suffix is empty. `capacity.do` returns a class-shaped object with only the counts non-null and `isFull` always null; `TeachingClass.mergeCapacity` overlays non-null fields and derives fullness from the counts.
- **`batch.do` leaves `canSelect` null.** The per-student `canSelect` and `noSelectReason` (e.g. 不在选课轮次范围内) are in `student/<code>.do` → `electiveBatchList`; `mergeBatchAvailability` combines them. `batchisopen.do` answers `msg "1"` for every round inside its time window, eligible or not, so it is only a time-window signal. The round notice (`xklcqr.do`) is a write and is only posted when `needConfirm == "1"`.
- **`unsuccessful.do` requires `isRead`** or answers `Required String parameter 'isRead' is not present`. `isRead=0` = rows not yet acknowledged (the official grab page pops them up after login), `isRead=1` = all rows (the sidebar list). Rows are drop-log shaped: `deleteOperateTypeName` (抽签落选) is the outcome, `deleteOperateTime` the time, `isConfirm` the acknowledgement, `wid` the id. The popup's 确认 posts `submit/unsuccessful.do?wids=<comma list>&studentCode=`; the app also remembers acknowledged wids per account (`Storage.acknowledgedUnsuccessful`) so the popup never repeats.
- **网课 (MOOC) classes are recognised by course-number prefix, not `teachingMethod`.** `ZH…` = 智慧树 (taught by 网络教师), `ey…` = 学习通 (taught by the 教务处 account), `yw…` = 知到; prefixes are case-sensitive and the rows carry no time or room. `面授讲课+SPOC/MOOC` is a blended classroom course (`TeachingClass.isBlended`), not 网课. See `kOnlineCoursePlatforms`.
- **`sysparam.do` carries the official tab names** (`displayNameXGXK` = 通识类选修课选课, `displayNameALLKC` = 全校课程查询, …) and `noDisplayVolunteer`; `dictionary.do` → `dictionaryList` carries the facet lists `XGXKLB` (通识类别, 13 codes), `KKDW` (开课单位, 28), `KCXZ`, `KCLB`, `TJCYY`. `publicinfo.do` is the index page's aggregate: `noticeList`, `commonProblemList`, `consultMethod` (教务处 029-87091714), `stopInfo`. `xkxf.do` `spCourseDescription` is the 通识 per-category credit requirement text the official 通识 tab shows above its list.
- **Textbooks:** `queryxsjxbbook.do` rows are `{"wid": "<JSON string>"}` with keys `JCBH` (code), `SM` (title), `ISBN`, `ZZZ` (author), `SFDG` (ordered), `WDGYY` (decline reason). Decline reasons come from `dictionary.do` → `TJCYY`. Textbook decisions are only asked for, and `needBook` only sent, when the round's `canSelectBook` is `"1"`.
- **Credits (`xkxf.do`):** `totalCredit` = 总学分, `getCredit` = 已获学分 (null before grades), `needCredit` = 已选学分 despite its name. There is no "still needed" figure.
- **`studentstatus.do`:** poll about once a second; `code "1"` = processed, `"-1"` = rejected (`msg` says why), anything else = still queued. Applies to drops too.
- **Whole-school query (`queryCourse.do`, QXKC)** is ~6400 flat rows (18 MB whole); the app pages it 100 at a time (`CourseService.fetchCatalogPage`) and sends the 通识类别 / 开课单位 facets as `queryContent` tokens `XGXKLBDM:<code>,KKDWDM:<code>,<text>` exactly as the official page does. Rows carry no capacity and `teacherName` like `王强(副教授)|2020110185|,…`; the official tab is query-only, and its 检查 button is `util/canchoose.do` → `data.reasonList`. Each round's `display*` flags say which category tabs exist.
- **`teachingTime.do`** returns one row per (class, weekday, week pattern): `dayOfWeek`, `beginSection`/`endSection`, `week` bit string (index i = week i+1, variable length), `weekName`, room-only `teachingPlace`.
- **The school gateway rate-limits captcha fetches.** Dozens of `vcode.do` calls in a few minutes get the client an HTML "Not allowed to visit this website" page while other endpoints keep working. Keep OCR retry budgets small.
- **Unsigned macOS rebuilds re-prompt the Keychain** ("flutter_secure_storage_service") on first secure-storage access; deny or allow, the app copes either way.
- **Two kinds of round.** `typeCode "02"` = 正选/抢课 (grablessons page, seat race); `typeCode "01"` = 预选 (curriculavariable page): every add carries `chooseVolunteer` ("1" = 第一志愿) in the key order chooseVolunteer → testTeachingClassID → needBook, capacity is judged by `numberOfFirstVolunteer` vs `classCapacity`, and `course/volunteer.do` (GET, `queryParam` with `teachingClassType` + `wid`) lists grades still open for a course (empty on this deployment, so the app falls back to `publicinfo/volunteer.do`). Rows of the 通识 round are flat (no `tcList`) and mostly `isConflict "1"`.
- **`该课程已存在预选课程结果中`** = you already hold another class of the same course; classified as `duplicateSelection` (hard stop). The tile warns before submitting.
- **Filed volunteers are not on `courseResult.do`.** In 预选 rounds it returns 0 rows; read `volunteerResult.do` (course rows with `tcList`, skip `isTest "1"`) and `publicCourseResult.do` (flat 通识 rows: `chooseVolunteer`, `numberOfFirstVolunteer`, `canDelete`, `selectStatus "01"`). Dropping is the same `deleteVolunteer.do`; reordering is `exchangeVolunteer.do` (operationType 3, `comment` = neighbour class id), not implemented. List rows mark a filed class with `chooseVolunteer`, not `isChoose`.
