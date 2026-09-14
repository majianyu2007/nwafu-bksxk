typedef NotificationTapCallback = void Function(String? payload);

class BrowserNotifications {
  bool get supported => false;
  String get permission => 'unsupported';

  Future<bool> requestPermission() async => false;

  void show({
    required String title,
    required String body,
    required String tag,
    String? payload,
    NotificationTapCallback? onTap,
  }) {}
}
