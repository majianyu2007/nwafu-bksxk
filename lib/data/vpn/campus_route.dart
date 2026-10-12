/// Decides how to reach campus services: directly (on campus, or anywhere
/// the school's hosts answer) or through the embedded VPN (off campus). The
/// VPN gateway itself refuses on-campus clients, so it is only tried after a
/// direct probe fails.
library;

import 'package:dio/dio.dart';

enum CampusRoute { unknown, direct, vpn, unreachable }

/// Probes [url] directly (bypassing [CampusProxy]); true when it answers.
typedef DirectProbe = Future<bool> Function(String url);

Future<bool> defaultDirectProbe(String url) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 4),
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ),
  );
  try {
    final r = await dio.get<String>(url);
    final code = r.statusCode ?? 0;
    final body = r.data ?? '';
    // The campus WAF answers off-campus clients with an HTML block page.
    return code > 0 && code < 500 && !body.contains('Not allowed to visit');
  } catch (_) {
    return false;
  } finally {
    dio.close(force: true);
  }
}

/// Hosts that must answer for the direct route to count.
const kCampusProbeUrls = [
  'https://authserver.nwafu.edu.cn/authserver/login',
  'https://ehall.nwafu.edu.cn/',
];

/// One retry: a cold start (DNS, wake from sleep) often fails the first
/// probe, and starting the VPN on campus would only fail at the gateway.
Future<bool> campusReachableDirectly([
  DirectProbe probe = defaultDirectProbe,
]) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    final results = await Future.wait(kCampusProbeUrls.map(probe));
    if (results.every((ok) => ok)) return true;
  }
  return false;
}
