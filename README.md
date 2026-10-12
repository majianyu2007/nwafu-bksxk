# 西农教务助手 · NWAFU Academic Assistant

A cross-platform Flutter client for everyday academic life at NWAFU:
timetable, grades, exams, free classrooms and course selection. Five tabs:
**课表 / 课程 / 抢课 / 成绩 / 我的**. One student ID and password work for the
unified identity (`authserver` / `ehall`), the selection system (`bksxk`) and
off-campus access (`vpn.nwafu.edu.cn`).

> This app is the client. The reverse-engineering research it is built on lives
> on the **`api` branch** of this repository (`docs/api.notes.md`,
> `docs/api.runtime.md`, `static-snapshot/`, etc.).
>
> **Build & deploy:** see [DEPLOYMENT.md](DEPLOYMENT.md). The web app needs the
> companion userscript in `web_bridge/` (v1.3.0+).
>
> **Network:** school traffic goes only to `*.nwafu.edu.cn`. Off campus the app
> can connect through the school VPN itself (built-in nwafu-connect, native
> platforms). Update checks contact GitHub and `mjy.js.org` without credentials.

## What's in 2.0

- **Fingerprint / Face ID sign-in** — after one password login the app registers
  its own passkey as a 生物识别 device on the unified identity (个人中心 →
  生物识别 shows it). Later logins use that key after a fingerprint / Face ID /
  device-passcode check: no password, no SMS code. Unbind in Settings or 个人中心.
- **One account** — the selection login is pre-filled from the unified account,
  and the remembered password is shared.
- **Off-campus access** — [nwafu-connect](https://github.com/majianyu2007/nwafu-connect)
  (branch `embed-lib`) is bundled as a native library. When the school's hosts are
  unreachable directly, the app logs in to the school VPN with the same password
  and routes `*.nwafu.edu.cn` through its local proxy; on campus it connects
  directly. Built in CI per platform (`tool/build-vpn-lib.sh` locally).
- **Timetable** — week grid and day view; full course names, room and teacher;
  stable per-course colours; current-time line; dimmed hatched classes from other
  weeks; custom courses (`1-16周(单)` syntax); exams on their day. Periods follow
  the school's 冬令/夏令 作息 (switching at 00:00 Beijing time on Oct 1 and May 1),
  with 午休 and 晚饭 bands like the printed timetable.
- **Updates and alerts** — the timetable and grades refresh automatically
  (Android in the background via WorkManager); changes such as a moved class or a
  new grade send a notification. Class and exam reminders.
- **Calendar** — sync to a dedicated 「西农课表」 system calendar (Android/iOS) or
  export `.ics` (all platforms), with configurable alarms.
- **More** — free classrooms (空教室) by day and period, grade CSV export, GPA
  trend, hide-scores toggle, Android home-screen widget for the current/next class,
  liquid-glass interface (can be turned off).

## Course selection

- **Full selection workflow in-app** — browse all course kinds (推荐/方案内/方案外/公选/重修/体育/辅修/全校), search, expand teaching classes, view full detail, select, and drop. No browser needed.
- **Accurate selection structs** — `volunteer.do` is built from the teaching-class flags: a class with `hasTest` must carry a chosen `testTeachingClassID`; a class needing textbook ordering must carry a `needBook` string. The app refuses to submit an incomplete/wrong struct rather than silently failing (enforced + unit-tested).
- **Background auto-grab monitor, made server-safe** — add any teaching class to a watch list; the engine polls capacity and, the instant a classmate drops and a seat opens, fires a **pre-built** grab request. It backs off on errors, **hard-stops** on captcha/account errors; normal mode also stops on maintenance/throttling, while rush mode backs off on transient throttle/network errors, never double-submits one seat, and only declares success after the server confirms it.
- **Captcha with manual fallback** — login/re-login prefetches and recognizes the image. A successful OCR result can submit filled credentials automatically; manual entry uses Enter or the login button. Wrong OCR answers retry within a fixed budget; credential errors return to manual entry. Late OCR results never overwrite a manually typed code.
- **Multiple accounts at once** (optional, off by default) — sign in several accounts as tabs; each keeps its own server session, watch list and monitor, so different accounts grab different courses in parallel.
- **Platform-specific background behavior** — desktop can close to a working tray; Android requests a foreground service while monitoring (OS limits and power management still apply). iOS must stay in the foreground. A closed web tab cannot monitor, and hidden tabs may be throttled. Notifications depend on platform support and permission.
- **Local whole-school catalogue** — first use fills a persistent catalogue in small background pages. Complete snapshots are searched locally without refresh-on-entry; explicit refresh or a changed account/server/campus/round/term scope starts a new fill. Failed refreshes retain the previous complete snapshot. Other course lists retain cache-first/live-refresh behavior.
- **Selection timetable retained** — the original selection-round overview remains under 课程 → 选课概览; it is separate from the everyday EMAP timetable.
- **Update notices** — settings offer manual app and web-bridge version checks; startup checks are throttled to once per day. New versions link to the official download/install page; nothing installs or restarts automatically.
- **Sessions that stay alive** — every account is pinged every 45 s; a dropped session can be re-authenticated with on-device OCR (enabled by default, up to 3 captcha attempts). Optional “被踢下线时让步” protection avoids repeated session contention with another device; it is off by default.
- **落选 popup** — courses lost in a lottery are shown once after login, exactly like the official site, and acknowledged to the server so they do not come back.
- **Typed errors + diagnostics** — every failure is classified (campus-network unreachable, timeout, session-expired, captcha, 5xx, course-full, batch-closed, maintenance, schema drift) with a specific message and remedy, never a bare “请求失败”. A diagnostics page probes reachability and exports a privacy-scrubbed report; the login screen shows a campus-network hint when the backend is unreachable.
- **System notifications** — grab success, 落选, and monitor auto-stop, named per account. Desktop + mobile.
- **Conflict-aware** — selecting a class the server marks as conflicting warns you (naming the conflict) *before* submitting.
- **网课 done right** — MOOC classes (智慧树 `ZH…`, 学习通 `ey…`, 知到 `yw…`) are recognised by course-number prefix and labelled with their platform; the 网课 filter and the 通识 credit requirements mirror the official tab.
- **Offline Chinese** — a bundled Noto Sans SC subset, with no font CDN.
- **Beautiful, adaptive UI** — Material 3, light/dark/system with a one-tap toggle and accent-color presets, plus platform dynamic color where available.

## Platforms and release status

See [PLATFORMS.md](PLATFORMS.md) for architecture choices, limitations and
validation status. The release workflow now defines Android ARM32/ARM64/x64,
Windows x64/ARM64, universal macOS, Linux x64/ARM64 and an unsigned iOS ARM64 IPA.
**A workflow definition is not a verified release**: successful jobs and device
smoke tests are required. Windows 32-bit is deliberately excluded.

HarmonyOS devices that support APK installation may use the corresponding Android
package. **Native HarmonyOS NEXT/5+ support is not implemented yet**: the selected
route is Flutter native, not ArkWeb. SDK and plugin migration blockers are tracked
in [docs/HARMONYOS.md](docs/HARMONYOS.md); no HAP is advertised or published.

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
│   ├── cas_client.dart         # unified identity, password/passkey and MFA
│   ├── ehall_service.dart      # read-only EMAP timetable/grades/exams
│   ├── edu_models.dart         # academic payload and cache models
│   ├── timetable_logic.dart    # school-time occurrences and reminder planning
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
│   ├── edu_providers.dart      # independent identity, scoped offline data and reminder lifecycle
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

Post-login round membership comes only from the student's `electiveBatchList`
and `expElectiveBatchList`, matching the official picker. Public `batch.do` rows
can fill metadata for matching ids but cannot add old/unrelated rounds or override
student eligibility and notice acknowledgement. A failed or malformed student
response is an error, not a fallback to the public list. Regression coverage:
`test/auth_context_test.dart`.

## Develop

Requires Flutter 3.44.6 / Dart 3.12.x (the locked dependencies require at least Flutter 3.44 / Dart 3.12). From the repo root:

```bash
flutter pub get
flutter test          # crypto, request parameters, monitoring, sessions and UI
flutter analyze       # clean
flutter run           # pick a device (android/ios/macos/windows/linux)
```

To build:

```bash
flutter build apk --release --split-per-abi  # Android: three smaller APKs
flutter build ipa         # iOS
flutter build macos       # macOS
flutter build windows --release  # uses native SDK architecture: x64 or ARM64
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
- Remembered passwords use `flutter_secure_storage` (native platform key storage; web uses its browser implementation). If secure storage is unavailable, saving the password fails gracefully. Passwords are sent only to the configured school server, encrypted exactly as the official site does.
- The server address is configurable in Settings in case the deployment moves.
