/// Web implementation: checks the global flag the companion userscript sets.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool get isWebRuntime => true;

/// The userscript sets window.__bksxkBridgeReady = true at document-start.
bool get isWebBridgeReady {
  try {
    final bridgeReady = web.window
        .getProperty<JSAny?>('__bksxkBridgeReady'.toJS)
        ?.dartify();
    if (bridgeReady == true) return true;
  } catch (_) {
    // Fall through to the DOM marker, which also works across isolated worlds.
  }

  return web.document.documentElement
          ?.getAttribute('data-bksxk-bridge-ready') ==
      'true';
}

void openWebBridgeInstaller() {
  final documentBaseUrl = web.document.baseURI;
  final appBaseUri = Uri.tryParse(documentBaseUrl) ?? Uri.base;
  final installerUrl = appBaseUri
      .resolve('../bksxk-web-bridge.user.js')
      .toString();
  web.window.open(installerUrl, '_blank', 'noopener');
}
