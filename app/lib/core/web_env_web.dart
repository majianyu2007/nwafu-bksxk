/// Web implementation: checks the global flag the companion userscript sets.
library;

import 'package:web/web.dart' as web;

bool get isWebRuntime => true;

/// The userscript sets window.__bksxkBridgeReady = true at document-start.
bool get isWebBridgeReady {
  try {
    final v = (web.window as dynamic).__bksxkBridgeReady;
    return v == true;
  } catch (_) {
    return false;
  }
}
