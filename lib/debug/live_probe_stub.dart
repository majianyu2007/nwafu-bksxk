/// Web stub for `live_probe.dart` so `main.dart` never imports `dart:io`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

String get probeResult => 'unavailable on web';
void probeRecheck(ProviderContainer c) {}
void probeBindDefault(ProviderContainer c) {}
void probeAnswerCaptcha(String code) {}
void probePasskeyLogin(ProviderContainer c) {}
void probeTimetableSync(ProviderContainer c) {}
void probeCampus(ProviderContainer c) {}
void probeDirect() {}
void probeRoomsMeta(ProviderContainer c) {}
void probeRoomsSample(ProviderContainer c) {}
void probeFetch(ProviderContainer c, String u) {}
void probeRoomsTiming(ProviderContainer c, int n) {}
void probeLibrary(ProviderContainer c) {}
void probeAcademic(ProviderContainer c) {}
