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
flutter test                                      # 63 tests, no network needed
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

`storageProvider` is overridden in `main()` with an opened `Storage`. Everything else derives from it: `apiClientProvider` → services → `sessionManagerProvider` → `monitorEngineProvider`. `captchaSolverProvider` picks `HttpOcrCaptchaSolver` when the user configured an OCR API, else the platform solver, and `sessionManagerProvider` listens to keep the manager's solver in sync. `selectionDataRevisionProvider` is a monotonic counter: bump it after any enrollment mutation or batch switch so `coursesProvider`, the selected page, etc. refetch. `monitor_providers.dart` bridges engine streams to the UI, persists the watch list on every engine change, and `notificationBridgeProvider` must stay watched from `RootShell` so notifications fire off-tab.

### Platform split via conditional imports

Web cannot use `dart:io`/`dart:ffi` and native must not import `dart:js_interop`, so three seams use `stub if (dart.library.X) impl` files:
- `core/web_env*.dart` — is-web + "is the CORS bridge userscript installed" checks.
- `data/captcha_solver_factory*.dart` — both sides currently return `OnnxCaptchaSolver`; on web it only works if `web/index.html` has loaded `window.ort` from `web/ort/`.
- `data/browser_notifications*.dart` — Web Notifications vs no-op; `NotificationService` wraps this plus `flutter_local_notifications`.

Keep new platform-specific code behind the same pattern; a bare `dart:io` import in shared code breaks `flutter build web`.

### Captcha OCR

The bundled model is `assets/models/autoverify.onnx` (quantized ddddocr CRNN from the AutoVerify extension, author-permitted) run through `flutter_onnxruntime`. Contract: input `[1,1,64,W]` float32 normalized to [-1,1], output int64 indices (ArgMax in-graph), CTC-collapse, charset in `autoverify_charset.json` (index 0 = blank). It is warmed up in `main()` before the login screen mounts. `solve()` returns null on any failure and the UI falls back to manual entry. **Do not** switch to the float ddddocr model, the old `onnxruntime` package, or a synthetically trained model — all were tried and miscompute or underperform on the native runtime. `tool/captcha_training/` and its README describe that abandoned synthetic model and are stale relative to the app.

### Web build

The school server sends no CORS headers, so the web app only works with the Tampermonkey/ScriptCat bridge in `web_bridge/bksxk-web-bridge.user.js`, which replaces `XMLHttpRequest` for the API host with `GM_xmlhttpRequest`. The app detects it via `window.__bksxkBridgeReady` or the `data-bksxk-bridge-ready` DOM attribute. If you change the deployed URL, update the `@match`/`@downloadURL` lines in the userscript header.

## Platform configuration that was hard-won

- **macOS keychain**: `Storage` uses `MacOsOptions(useDataProtectionKeyChain: false)` because the data-protection keychain needs a real code signature (errSecMissingEntitlement / -34018 on unsigned builds). All secure-storage calls are try/caught and flip `secureStorageAvailable`. Do not add a `keychain-access-groups` entitlement.
- **macOS entitlements**: `com.apple.security.network.client` must be in both `DebugProfile.entitlements` and `Release.entitlements`; without it the sandbox silently blocks all network. `macos/Runner/Info.plist` sets `NSAllowsLocalNetworking` so a `localhost` simulator origin is allowed.
- **macOS deployment target is 14.0** (required by `flutter_onnxruntime`); `macos/Podfile` forces it on every pod in `post_install`.
- **Android**: `INTERNET` and `POST_NOTIFICATIONS` live in the **main** manifest; Flutter only auto-adds `INTERNET` to debug/profile.
- **Fonts**: Noto Sans SC GB2312/GBK subset is bundled in `assets/fonts/`; the app must never contact a font CDN. The only network peer is the school server (plus a user-configured OCR API if set).

## Safety

`volunteer.do`, `deleteVolunteer.do`, `addbook.do`, and `modifybook.do` change real enrollment state. They run only on explicit user action (drops behind a confirmation dialog) or from an armed watch the user created. Never add code paths that fire them automatically for testing; use fakes or the `testserver` branch's local simulator.

## Live-server facts (verified against bksxk.nwafu.edu.cn on 2026-09-14, read-only)

These contradict reasonable assumptions and are locked by `test/live_payloads_test.dart`:

- **One session per account.** A new login (app, browser, curl) invalidates the previous token; the old client gets `code "302" / 未查询到登录信息`. The client's silent re-login (captcha OCR, `Storage.silentReloginAttempts`, default 3) handles this; when it fails the session enters `AuthPhase.expired` and `ReloginDialog` asks the user.
- **`capacitySuffix` is `""` on every class.** The parameter must still be sent (the server rejects its absence); an empty value is fine. Never skip the capacity poll because the suffix is empty. `capacity.do` returns a class-shaped object with only the counts non-null and `isFull` always null; `TeachingClass.mergeCapacity` overlays non-null fields and derives fullness from the counts.
- **`batch.do` leaves `canSelect` null.** The per-student `canSelect` and `noSelectReason` (e.g. 不在选课轮次范围内) are in `student/<code>.do` → `electiveBatchList`; `mergeBatchAvailability` combines them. `batchisopen.do` answers `msg "1"` for every round inside its time window, eligible or not, so it is only a time-window signal. The round notice (`xklcqr.do`) is a write and is only posted when `needConfirm == "1"`.
- **`unsuccessful.do` requires `isRead`** (`0` for the list) or answers `Required String parameter 'isRead' is not present`.
- **Textbooks:** `queryxsjxbbook.do` rows are `{"wid": "<JSON string>"}` with keys `JCBH` (code), `SM` (title), `ISBN`, `ZZZ` (author), `SFDG` (ordered), `WDGYY` (decline reason). Decline reasons come from `dictionary.do` → `TJCYY`. Textbook decisions are only asked for, and `needBook` only sent, when the round's `canSelectBook` is `"1"`.
- **Credits (`xkxf.do`):** `totalCredit` = 总学分, `getCredit` = 已获学分 (null before grades), `needCredit` = 已选学分 despite its name. There is no "still needed" figure.
- **`studentstatus.do`:** poll about once a second; `code "1"` = processed, `"-1"` = rejected (`msg` says why), anything else = still queued. Applies to drops too.
- **Whole-school query (`queryCourse.do`, QXKC)** rows carry no capacity and `teacherName` like `王强(副教授)|2020110185|,…`; the official tab is query-only. Each round's `display*` flags say which category tabs exist.
- **`teachingTime.do`** returns one row per (class, weekday, week pattern): `dayOfWeek`, `beginSection`/`endSection`, `week` bit string (index i = week i+1, variable length), `weekName`, room-only `teachingPlace`.
- **The school gateway rate-limits captcha fetches.** Dozens of `vcode.do` calls in a few minutes get the client an HTML "Not allowed to visit this website" page while other endpoints keep working. Keep OCR retry budgets small.
- **Unsigned macOS rebuilds re-prompt the Keychain** ("flutter_secure_storage_service") on first secure-storage access; deny or allow, the app copes either way.
