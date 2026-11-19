import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

typedef NotificationTapCallback = void Function(String? payload);

class BrowserNotifications {
  bool get supported {
    try {
      return globalContext.has('Notification');
    } catch (_) {
      return false;
    }
  }

  String get permission {
    if (!supported) return 'unsupported';
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'denied';
    }
  }

  Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      final result = await web.Notification.requestPermission().toDart;
      return result.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  void show({
    required String title,
    required String body,
    required String tag,
    String? payload,
    NotificationTapCallback? onTap,
  }) {
    if (!supported || permission != 'granted') return;
    try {
      final notification = web.Notification(
        title,
        web.NotificationOptions(
          body: body,
          tag: tag,
          icon: 'icons/Icon-192.png',
        ),
      );
      notification.onclick = ((web.Event event) {
        web.window.focus();
        notification.close();
        onTap?.call(payload);
      }).toJS;
    } catch (_) {
      // Some browsers (Chrome on Android) only allow notifications from a
      // service worker and throw here; degrade silently like native does.
    }
  }
}
