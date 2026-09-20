/// Web: nothing keeps a closed tab alive; every call is a no-op.
library;

import 'background.dart';

Future<void> init() async {}
void attach(BackgroundHost host) {}
Future<void> setMonitoring(bool running,
    {required bool runInBackground, required bool keepAwake}) async {}
Future<void> setCloseToTray(bool enabled) async {}
Future<void> updateStatus(String text) async {}
bool get supportsTray => false;
bool get supportsForegroundService => false;
