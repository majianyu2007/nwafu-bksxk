# 西农本科选课 · NWAFU Course Grabber

A cross-platform Flutter client for the NWAFU (`bksxk.nwafu.edu.cn`) undergraduate
course selection system. Built for one thing above all: **being faster than the
person next to you** at selecting and grabbing courses. (Named 本科 to leave room
for a separate graduate system.)

> This app is the client. The reverse-engineering research it is built on lives
> on the **`api` branch** of this repository (`docs/api.notes.md`,
> `docs/api.runtime.md`, `static-snapshot/`, etc.). The app faithfully ports the
> site's request construction — most importantly the login password cipher and
> the course-selection request structs — and verifies them against ground-truth
> vectors captured from the real site JS.
>
> **Build & deploy:** see [DEPLOYMENT.md](DEPLOYMENT.md) (macOS needs full Xcode;
> web needs a companion Tampermonkey bridge for CORS).
>
> **Network:** the app only ever talks to `https://bksxk.nwafu.edu.cn`, which is
> reachable **only on the campus network** (use the school VPN off-campus).

## Feature highlights

- **Full selection workflow in-app** — browse all course kinds (推荐/方案内/方案外/公选/重修/体育/辅修/全校), search, expand teaching classes, view full detail, select, and drop. No browser needed.
- **Accurate selection structs** — `volunteer.do` is built from the teaching-class flags: a class with `hasTest` must carry a chosen `testTeachingClassID`; a class needing textbook ordering must carry a `needBook` string. The app refuses to submit an incomplete/wrong struct rather than silently failing (enforced + unit-tested).
- **Background auto-grab monitor, made server-safe** — add any teaching class to a watch list; the engine polls capacity and, the instant a classmate drops and a seat opens, fires a **pre-built** grab request. It backs off on errors, **hard-stops** on captcha/account/maintenance/throttle signals instead of hammering, never double-submits one seat, and only declares success after the server confirms it.
- **Fast captcha** — the captcha only gates login/re-login (grabbing uses the `token` header alone), so the login screen prefetches the image, autofocuses the field, and auto-submits the moment the code is entered. An OCR solver is pluggable for hands-free re-login.
- **Multiple accounts at once** (optional, off by default) — sign in several accounts as tabs; each keeps its own server session, watch list and monitor, so different accounts grab different courses in parallel.
- **Runs in the background** — desktop closes to a tray icon and keeps polling; Android runs a foreground service while a monitor is active; results and errors arrive as system notifications on every platform.
- **Instant lists** — every course list is cached on the device and shown at once while the fresh copy loads. Passwords are stored in the platform keychain/keystore; saved accounts appear as one-tap chips on the login screen.
- **Sessions that stay alive** — every account is pinged every 45 s; a dropped session can be re-authenticated with on-device OCR (enabled by default, up to 3 captcha attempts). Optional “被踢下线时让步” protection avoids repeated session contention with another device; it is off by default.
- **落选 popup** — courses lost in a lottery are shown once after login, exactly like the official site, and acknowledged to the server so they do not come back.
- **Typed errors + diagnostics** — every failure is classified (campus-network unreachable, timeout, session-expired, captcha, 5xx, course-full, batch-closed, maintenance, schema drift) with a specific message and remedy, never a bare “请求失败”. A diagnostics page probes reachability and exports a privacy-scrubbed report; the login screen shows a campus-network hint when the backend is unreachable.
- **System notifications** — grab success, 落选, and monitor auto-stop, named per account. Desktop + mobile.
- **Conflict-aware** — selecting a class the server marks as conflicting warns you (naming the conflict) *before* submitting.
- **网课 done right** — MOOC classes (智慧树 `ZH…`, 学习通 `ey…`, 知到 `yw…`) are recognised by course-number prefix and labelled with their platform; the 网课 filter and the 通识 credit requirements mirror the official tab.
- **Offline Chinese** — a bundled Noto Sans SC subset (no font CDN), so nothing but the school server is ever contacted.
- **Beautiful, adaptive UI** — Material 3, light/dark/system with a one-tap toggle and accent-color presets, plus platform dynamic color where available.

## Architecture

```
lib/
├── core/
│   ├── constants.dart          # endpoints + CourseKind enum (teachingClassType codes)
│   └── crypto/des_login.dart   # faithful port of the site's strEnc login cipher
├── data/
│   ├── models.dart             # CourseRow, TeachingClass (grab flags), Batch, ApiResult
│   ├── param_builders.dart     # querySetting / addParam / deleteParam — byte-identical to the site
│   ├── api_client.dart         # Dio + cookies + token header + silent-relogin interceptor
│   ├── auth_service.dart       # login sequence + SessionManager (owns token, re-login)
│   ├── captcha.dart            # CaptchaSolver abstraction
│   ├── course_service.dart     # queries, catalogue paging, capacity refresh, textbooks, 落选
│   ├── enroll_service.dart     # add/drop + status polling (resolve → submit split)
│   ├── info_service.dart       # sysparam, dictionary, publicinfo, credits
│   ├── onnx_captcha_solver.dart# on-device ONNX captcha OCR (auto-recognize)
│   ├── notifications.dart      # system notifications for grab/seat events
│   ├── storage.dart            # secure passwords + accounts + watch-list + prefs
│   └── monitor_engine.dart     # the auto-grab engine (per-watch poll loops, rush mode, gate)
├── app/
│   ├── providers.dart          # per-account SessionScope family, theme, settings
│   ├── monitor_providers.dart  # per-account engine → UI bridge, plan mode
│   └── theme.dart              # Material 3 theme (light/dark, seed color)
└── ui/                         # login, home, courses, monitor, selected, settings pages
```

### Why the grab is fast

The add request is split into **resolve** and **submit**. When you arm a watch,
`resolveAddParam` runs immediately and builds the complete form body — including
any experiment class and textbook selection. When a seat opens, the engine only
calls `submitAdd(plan)`: one POST, no branching, no extra lookups. Anything that
could require a decision (which experiment class? order the textbook?) is settled
up front, so the hot path is pure network latency.

### Correctness: login crypto & request structs

The login password is `base64(strEnc(password, "this","password","is"))`, where
`strEnc` is the site's bespoke triple-key DES-like cipher (UTF-16 code units, hex
output). It is transliterated in `des_login.dart` and **verified byte-for-byte**
against vectors generated by running the real `des.min.js` under Node
(`test/des_login_vectors.json`). The request-param builders are likewise checked
against the site's key order and separators.

## Develop

Requires Flutter (stable). From the repo root:

```bash
flutter pub get
flutter test          # crypto, request parameters, monitoring, sessions and UI
flutter analyze       # clean
flutter run           # pick a device (android/ios/macos/windows/linux)
```

To build:

```bash
flutter build apk         # Android
flutter build ipa         # iOS
flutter build macos       # macOS
flutter build windows     # Windows
flutter build linux       # Linux
```

## Tests

| Suite | What it locks down |
| --- | --- |
| `des_login_test.dart` | `loginPwd` is byte-identical to the site for 12 passwords incl. unicode + multi-block |
| `param_builders_test.dart` | querySetting/addParam/deleteParam key order; `hasTest`/`hasBook` submission rules |
| `monitor_engine_test.dart` | grabs once on open seat; refuses to grab without a required test class; resumes after setup; hard-stops on throttle; confirms before declaring success; no double-submit |

## Safety notes

- Write operations (`volunteer.do`, `deleteVolunteer.do`, textbook order/cancel) change real enrollment state. The app performs them only on explicit user action, and drops require a confirmation dialog.
- Stopping, pausing or removing a watch prevents a late capacity response from submitting. Logging out disposes the account's monitor; pending results cannot start a new confirmation or publish events after disposal. Requests already sent to the server cannot be recalled.
- Passwords are stored via `flutter_secure_storage` and only ever sent to the school server, encrypted exactly as the official site does.
- The server address is configurable in Settings in case the deployment moves.
