/// Web-runtime helpers: detect whether the app is running in a browser and
/// whether the companion CORS bridge userscript is installed.
///
/// On native platforms these are trivially false/true and no prompt is shown.
/// The actual browser check is delegated to a conditional import so the native
/// build never references dart:js_interop.
library;

import 'web_env_stub.dart' if (dart.library.js_interop) 'web_env_web.dart' as impl;

/// True only when running as a web app in a browser.
bool get isWebRuntime => impl.isWebRuntime;

/// True when the companion userscript (bksxk-web-bridge.user.js) has installed
/// its XHR bridge (it sets window.__bksxkBridgeReady). Always true off-web,
/// since native has no CORS restriction.
bool get isWebBridgeReady => impl.isWebBridgeReady;
