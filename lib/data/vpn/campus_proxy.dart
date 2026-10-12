/// One switch every campus HTTP client consults: while the embedded VPN is
/// up, requests to *.nwafu.edu.cn go through its local proxy; otherwise they
/// connect directly. Other hosts (GitHub update checks, OCR) never use it.
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

  static bool isCampusHost(String host) =>
      host == 'nwafu.edu.cn' || host.endsWith('.nwafu.edu.cn');

  /// The `findProxy` answer for [uri].
  String route(Uri uri) {
    final a = address;
    return a != null && isCampusHost(uri.host) ? 'PROXY $a' : 'DIRECT';
  }

  /// Makes [dio] honour the switch (no-op on web).
  void attach(Dio dio) => impl.attachCampusProxy(dio, this);
}
