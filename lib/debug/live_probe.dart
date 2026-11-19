/// Debug-only helpers driven from the Dart VM service during live checks.
/// Nothing here runs unless evaluated from a debugger.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/campus_access.dart';
import '../app/edu_providers.dart';
import '../app/providers.dart' show storageProvider, themeControllerProvider;
import '../data/academic_calendar.dart' show schoolDate;
import '../data/ehall_service.dart';
import '../data/library_service.dart';
import '../data/timetable_logic.dart';
import '../data/vpn/campus_route.dart';

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
      _captchaAnswer?.call(null);
      final answer = Completer<String?>();
      _captchaAnswer = answer.complete;
      probeResult = 'captcha $captchaPath';
      try {
        return await answer.future;
      } finally {
        if (identical(_captchaAnswer, answer.complete)) {
          _captchaAnswer = null;
        }
      }
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
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 4),
    followRedirects: false,
    validateStatus: (_) => true,
    responseType: ResponseType.plain,
  ));
  try {
    for (final u in kCampusProbeUrls) {
      try {
        final r = await dio.get<String>(u);
        out[u] = r.statusCode;
      } catch (e) {
        out[u] = '$e'.split('\n').first;
      }
    }
  } finally {
    dio.close(force: true);
  }
  return out;
});

String _todayYmd() {
  final d = schoolDate(DateTime.now());
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

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
    'KXRQ': _todayYmd(),
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

void probeRoomsTiming(ProviderContainer c, int size) => probe(() async {
  final dio = c.read(eduClientProvider).cas.dio;
  await c.read(eduClientProvider).ehall.activate(EmapApp.rooms);
  final sw = Stopwatch()..start();
  final r = await dio.post<String>(
    '$kEhallOrigin/jwapp/sys/kxjas/modules/kxjscx/cxkxjs.do',
    data: {'KXRQ': _todayYmd(), 'KSJC': '1', 'JSJC': '2', 'pageSize': '$size', 'pageNumber': '1'},
    options: Options(contentType: Headers.formUrlEncodedContentType),
  );
  final j = jsonDecode(r.data!) as Map;
  final b = (j['datas'] as Map)['cxkxjs'] as Map;
  return {'ms': sw.elapsedMilliseconds, 'rows': (b['rows'] as List).length, 'total': b['totalSize'], 'bytes': r.data!.length};
});

void probeLibrary(ProviderContainer c) => probe(() async {
  final lib = LibraryService(
    c.read(eduClientProvider).cas,
    onLoginRequired: c.read(eduSessionProvider.notifier).silentRelogin,
  );
  final today = DateTime.now();
  final seats = await lib.areas(LibraryKind.seat, today);
  final rooms = await lib.areas(LibraryKind.space, today);
  final mine = await lib.seatBookings();
  final m = await lib.member();
  String rb;
  try {
    rb = (await lib.roomBookings()).length.toString();
  } catch (e) {
    rb = 'ERR $e';
  }
  return 'seats ${seats.length} first ${seats.isEmpty ? '' : '${seats.first.campus}/${seats.first.floor}/${seats.first.name} ${seats.first.free}/${seats.first.total}'}\n'
      'rooms ${rooms.length} first ${rooms.isEmpty ? '' : '${rooms.first.name} cap ${rooms.first.capacity} ${rooms.first.typeName}'}\n'
      'mySeat ${mine.length} first ${mine.isEmpty ? '' : '${mine.first.place} ${mine.first.seat} ${mine.first.day} ${mine.first.statusName}'}\n'
      'roomBookings $rb\nmember ${m.roleName} qr ${m.qrImage != null}';
});

void probeBindDefault(ProviderContainer c) => probeBind(
  c,
  passwordPath: '${Directory.systemTemp.path}/pw',
  captchaPath: '${Directory.systemTemp.path}/captcha.png',
  deviceName: '西农教务助手 · Mac',
);

void probeAcademic(ProviderContainer c) => probe(() async {
  final client = c.read(eduClientProvider);
  final studentId = c.read(eduSessionProvider).account?.username ?? '';
  final out = StringBuffer();
  try {
    final a = await client.ehall.degreeAudit(studentId);
    out.writeln('degree ok: ${a.toString().substring(0, a.toString().length.clamp(0, 400))}');
  } catch (e) {
    out.writeln('degree ERR $e');
  }
  try {
    final inbox = await client.portal.unreadCount();
    out.writeln('unread $inbox');
  } catch (e) {
    out.writeln('portal ERR $e');
  }
  return out.toString();
});

void probeTheme(ProviderContainer c, bool dark) => c
    .read(themeControllerProvider.notifier)
    .setMode(dark ? ThemeMode.dark : ThemeMode.light);

void probeShiftClock(ProviderContainer c, int minutes) =>
    c.read(debugClockOffsetProvider.notifier).state = Duration(minutes: minutes);

String probeDay(ProviderContainer c, int y, int m, int d) => c
    .read(timetableProvider)
    .data!
    .classesOn(DateTime.utc(y, m, d))
    .map(
      (o) =>
          '${o.session.courseName} ${o.session.startPeriod}-${o.session.endPeriod} ${o.session.room}',
    )
    .join('; ');
