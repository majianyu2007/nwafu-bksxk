/// Debug-only helpers driven from the Dart VM service during live checks.
/// Nothing here runs unless evaluated from a debugger.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dio/dio.dart';

import '../app/campus_access.dart';
import '../data/ehall_service.dart';
import '../data/vpn/campus_route.dart';
import '../app/edu_providers.dart';
import '../app/providers.dart' show storageProvider;

String probeResult = '';

/// Starts [task] and stores its outcome in [probeResult].
void probe(Future<Object?> Function() task) {
  probeResult = 'pending';
  task().then(
    (v) => probeResult = 'ok ${v is String ? v : jsonEncode(v)}',
    onError: (Object e, StackTrace st) => probeResult = 'error $e\n$st',
  );
}

/// Read-only: does adding a device need the password re-check?
void probeRecheck(ProviderContainer c) => probe(() async {
  final cas = c.read(eduClientProvider).cas;
  await cas.openPersonalCenter();
  return {
    'needsRecheck': await cas.personalCenterNeedsRecheck(),
    'devices': await cas.boundDevices(),
  };
});

void Function(String?)? _captchaAnswer;

/// Live bind of this app as a passkey device. The re-check captcha image is
/// written to [captchaPath]; answer with [probeAnswerCaptcha].
void probeBind(
  ProviderContainer c, {
  required String passwordPath,
  required String captchaPath,
  required String deviceName,
}) => probe(() async {
  final password = (await File(passwordPath).readAsString()).trim();
  await c.read(eduSessionProvider.notifier).bindThisDevice(
    deviceName: deviceName,
    password: password,
    solveCaptcha: (image) async {
      await File(captchaPath).writeAsBytes(image);
      final answer = Completer<String?>();
      _captchaAnswer = answer.complete;
      probeResult = 'captcha $captchaPath';
      return answer.future;
    },
  );
  final account = c.read(eduSessionProvider).account!.username;
  final raw = await c.read(storageProvider).eduDeviceKey(account);
  final saved = jsonDecode(raw!) as Map<String, dynamic>;
  return {
    'bound': true,
    'deviceBindingId': saved['deviceBindingId'],
    'credentialId': saved['credentialId'],
  };
});

void probeAnswerCaptcha(String code) {
  final f = _captchaAnswer;
  _captchaAnswer = null;
  probeResult = 'pending';
  f?.call(code);
}

/// Logs out of CAS only (keeps the device key) and signs in with it,
/// skipping the biometric prompt (the probe is the user's stand-in).
void probePasskeyLogin(ProviderContainer c) => probe(() async {
  final s = c.read(eduSessionProvider.notifier);
  final user = c.read(eduSessionProvider).account!.username;
  await c.read(eduClientProvider).cas.clearSession();
  c.read(eduClientProvider).ehall.reset();
  await s.loginWithDeviceKey(user, () async => true);
  final st = c.read(eduSessionProvider);
  return {'signedIn': st.signedIn, 'name': st.account?.name};
});

void probeTimetableSync(ProviderContainer c) => probe(() async {
  await c.read(timetableProvider.notifier).sync();
  final s = c.read(timetableProvider);
  return {'sessions': s.data?.sessions.length, 'error': s.error?.message};
});

void probeCampus(ProviderContainer c) => probe(() async {
  final ctl = c.read(campusAccessProvider.notifier);
  await ctl.check();
  final st = c.read(campusAccessProvider);
  final status = await c.read(vpnBridgeProvider).status();
  return {
    'vpnLibLoaded': ctl.vpnAvailable,
    'route': st.route.name,
    'message': st.message,
    'libStatus': status.state,
  };
});

void probeDirect() => probe(() async {
  final out = <String, Object?>{};
  for (final u in kCampusProbeUrls) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 4),
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ));
    try {
      final r = await dio.get<String>(u);
      out[u] = r.statusCode;
    } catch (e) {
      out[u] = '$e'.split('\n').first;
    }
  }
  return out;
});

/// Read-only: the 空闲教室 app's query model (field names, code lists).
void probeRoomsMeta(ProviderContainer c) => probe(() async {
  final ehall = c.read(eduClientProvider).ehall;
  await ehall.activate(EmapApp.rooms);
  final dio = c.read(eduClientProvider).cas.dio;
  final r = await dio.post<String>(
    '$kEhallOrigin/jwapp/sys/kxjas/modules/kxjscx.do',
    data: {'*json': '1'},
    options: Options(contentType: Headers.formUrlEncodedContentType),
  );
  final j = jsonDecode(r.data!) as Map<String, dynamic>;
  final out = <String>[];
  for (final m in j['models'] as List) {
    out.add('MODEL ${m['name']} ${m['url']}');
    for (final ctl in m['controls'] as List) {
      out.add('  ${ctl['name']} ${ctl['caption']} ${ctl['xtype']} '
          '${ctl['search.xtype'] ?? ''} ${ctl['url'] ?? ''} '
          '${ctl['search.hidden'] == true ? 'H' : ''}');
    }
  }
  return out.join('\n');
});

void probeRoomsSample(ProviderContainer c) => probe(() async {
  final ehall = c.read(eduClientProvider).ehall;
  final dio = c.read(eduClientProvider).cas.dio;
  Future<String> post(String path, Map<String, dynamic> form) async =>
      (await dio.post<String>(
        '$kEhallOrigin$path',
        data: form,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      )).data!;
  await ehall.activate(EmapApp.rooms);
  final campus = (await dio.get<String>('$kEhallOrigin/jwapp/code/83a986fc-e677-400e-99a4-c7bb39c2ca35.do')).data!;
  final building = (await dio.get<String>('$kEhallOrigin/jwapp/code/551fbcc3-cf07-4566-af1e-fc7ce272ddc1.do')).data!;
  final rows = await post('/jwapp/sys/kxjas/modules/kxjscx/cxkxjs.do', {
    'KXRQ': '2026-10-13',
    'KSJC': '1',
    'JSJC': '2',
    'pageSize': '3',
    'pageNumber': '1',
  });
  String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
  return 'CAMPUS ${cut(campus, 600)}\nBUILDING ${cut(building, 900)}\nROWS ${cut(rows, 1500)}';
});

void probeFetch(ProviderContainer c, String url) => probe(() async {
  final dio = c.read(eduClientProvider).cas.dio;
  final r = await dio.get<String>(url);
  return r.data ?? '';
});
