import 'dart:js_interop';

import 'package:web/web.dart' as web;

typedef NotificationTapCallback = void Function(String? payload);

class BrowserNotifications {
  bool get supported => true;
  String get permission => web.Notification.permission;

  Future<bool> requestPermission() async {
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart == 'granted';
  }

  void show({
    required String title,
    required String body,
    required String tag,
    String? payload,
    NotificationTapCallback? onTap,
  }) {
    if (permission != 'granted') return;
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
  }
}
