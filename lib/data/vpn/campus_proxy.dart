/// One switch every campus HTTP client consults: while the embedded VPN is
/// up, requests to the campus-only hosts (the course selection system) go
/// through its local proxy; everything else, including the unified identity
/// and ehall which answer from the internet, connects directly.
library;

import 'package:dio/dio.dart';

import 'campus_proxy_stub.dart'
    if (dart.library.io) 'campus_proxy_io.dart'
    as impl;

class CampusProxy {
  CampusProxy._();
  static final instance = CampusProxy._();

  /// `127.0.0.1:<port>` while the VPN runs, else null.
  String? address;

  /// Hosts only reachable on the campus network.
  static const campusOnlyHosts = {'bksxk.nwafu.edu.cn'};

  /// Optional custom selection host configured in Settings, if overridden.
  String? customCampusHost;

  bool isCampusHost(String host) {
    final normalized = host.toLowerCase();
    if (campusOnlyHosts.contains(normalized)) return true;
    final custom = customCampusHost?.trim().toLowerCase();
    return custom != null && custom.isNotEmpty && custom == normalized;
  }

  /// The `findProxy` answer for [uri].
  String route(Uri uri) {
    final a = address;
    return a != null && isCampusHost(uri.host) ? 'PROXY $a' : 'DIRECT';
  }

  /// Makes [dio] honour the switch (no-op on web).
  void attach(Dio dio) => impl.attachCampusProxy(dio, this);
}
