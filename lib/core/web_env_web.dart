/// Web implementation: checks the global flag the companion userscript sets.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'update_links.dart';

bool get isWebRuntime => true;

bool _readBoolFlag(String jsProp, String domAttr) {
  try {
    if (web.window.getProperty<JSAny?>(jsProp.toJS)?.dartify() == true) {
      return true;
    }
  } catch (_) {
    // Fall through to the DOM marker, which also works across isolated worlds.
  }
  return web.document.documentElement?.getAttribute(domAttr) == 'true';
}

/// The userscript sets window.__bksxkBridgeReady = true at document-start.
bool get isWebBridgeReady =>
    _readBoolFlag('__bksxkBridgeReady', 'data-bksxk-bridge-ready');

bool get isEduSessionBridgeReady => _readBoolFlag(
      '__bksxkEduSessionBridgeReady',
      'data-bksxk-edu-session-bridge-ready',
    );

bool get isCasLoginBridgeReady => _readBoolFlag(
      '__bksxkCasLoginBridgeReady',
      'data-bksxk-cas-login-bridge-ready',
    );

String? get installedWebBridgeVersion {
  try {
    final version =
        web.window.getProperty<JSAny?>('__bksxkBridgeVersion'.toJS)?.dartify();
    if (version is String && version.trim().isNotEmpty) return version.trim();
  } catch (_) {
    // Script managers may isolate globals; use their shared DOM marker.
  }
  final version = web.document.documentElement
      ?.getAttribute('data-bksxk-bridge-version')
      ?.trim();
  return version == null || version.isEmpty ? null : version;
}

void openWebBridgeInstaller() {
  web.window
      .open(bridgeInstallerUri.toString(), '_blank', 'noopener,noreferrer');
}
