/// Web-runtime helpers: detect whether the app is running in a browser and
/// whether the companion CORS bridge userscript is installed.
///
/// On native platforms these are trivially false/true and no prompt is shown.
/// The actual browser check is delegated to a conditional import so the native
/// build never references dart:js_interop.
library;

import 'package:pub_semver/pub_semver.dart';

import 'web_env_stub.dart' if (dart.library.js_interop) 'web_env_web.dart'
    as impl;

/// Recommended companion bridge version for full web capability (in-app CAS
/// login, MFA, auto-relogin, fresh-node bksxk routing, portal, and library).
const String kRecommendedWebBridgeVersion = '1.5.1';

/// True only when running as a web app in a browser.
bool get isWebRuntime => impl.isWebRuntime;

/// True when the companion userscript (bksxk-web-bridge.user.js) has installed
/// its XHR bridge (it sets window.__bksxkBridgeReady). Always true off-web,
/// since native has no CORS restriction.
bool get isWebBridgeReady => impl.isWebBridgeReady;

/// True when the bridge supports academic hosts (`ehall`, etc.).
bool get isEduSessionBridgeReady => impl.isEduSessionBridgeReady;

/// Installed bridge version, or null when absent, native, or a legacy script.
String? get installedWebBridgeVersion => impl.installedWebBridgeVersion;

String? _cachedRawVersion;
Version? _cachedParsedVersion;

Version? _parsedBridgeVersion() {
  final raw = installedWebBridgeVersion;
  if (raw == null) return null;
  if (raw == _cachedRawVersion) return _cachedParsedVersion;
  _cachedRawVersion = raw;
  final trimmed = raw.startsWith('v') || raw.startsWith('V')
      ? raw.substring(1)
      : raw;
  try {
    _cachedParsedVersion = Version.parse(trimmed);
  } catch (_) {
    _cachedParsedVersion = null;
  }
  return _cachedParsedVersion;
}

bool _bridgeVersionAtLeast(Version min) {
  final parsed = _parsedBridgeVersion();
  return parsed != null && parsed >= min;
}

final _vFullCampus = Version(1, 4, 2);
final _vFreshRoute = Version(1, 4, 3);
final _vCasLogin = Version(1, 5, 0);

/// True on native, or on web when the bridge script is >= 1.4.2 (supporting
/// newehall portal and full booking-lib floorplan images & seminar endpoints).
bool get isFullCampusBridgeReady {
  if (!isWebRuntime) return true;
  return isEduSessionBridgeReady && _bridgeVersionAtLeast(_vFullCampus);
}

/// True on web when the bridge script is >= 1.4.3 (supporting isolated bksxk
/// cookies and fresh-node route pinning via X-Bksxk-Refresh-Route).
bool get isFreshRouteBridgeReady {
  if (!isWebRuntime || !isWebBridgeReady) return false;
  return _bridgeVersionAtLeast(_vFreshRoute);
}

/// True on web when the bridge script is >= 1.5.0 (supporting in-app unified
/// identity CAS login, MFA, logout, and silent auto-relogin without opening
/// the school webpage).
bool get isCasLoginBridgeReady {
  if (!isWebRuntime || !isWebBridgeReady) return false;
  return impl.isCasLoginBridgeReady || _bridgeVersionAtLeast(_vCasLogin);
}

/// Opens the deployed userscript URL so Tampermonkey or ScriptCat can install
/// the web bridge directly. This is a no-op on native platforms.
void openWebBridgeInstaller() => impl.openWebBridgeInstaller();
