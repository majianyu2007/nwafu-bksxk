import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'campus_proxy.dart';

void attachCampusProxy(Dio dio, CampusProxy proxy) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()..findProxy = proxy.route,
  );
}
