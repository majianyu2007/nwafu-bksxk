/// An OCR captcha solver that POSTs the captcha image to a user-configured HTTP
/// endpoint (e.g. a self-hosted ddddocr server). For users who prefer their own
/// recognizer over the bundled on-device model.
///
/// The request/response shape is configurable to fit common self-hosted servers:
///   - send as multipart file, base64 in JSON, or raw body bytes,
///   - read the answer from plain text or a JSON field.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'captcha.dart';

/// How the captcha image is sent to the OCR endpoint.
enum OcrRequestFormat { multipart, base64Json, rawBytes }

/// How the recognized text is read from the response.
enum OcrResponseFormat { plainText, jsonField }

class OcrApiConfig {
  const OcrApiConfig({
    required this.url,
    this.requestFormat = OcrRequestFormat.base64Json,
    this.imageField = 'image',
    this.responseFormat = OcrResponseFormat.jsonField,
    this.responseField = 'result',
    this.headers = const {},
  });

  final String url;
  final OcrRequestFormat requestFormat;

  /// Field name for the image (multipart file field or JSON key).
  final String imageField;
  final OcrResponseFormat responseFormat;

  /// JSON key holding the recognized text (when responseFormat is jsonField).
  final String responseField;
  final Map<String, String> headers;

  bool get isValid => url.trim().isNotEmpty && Uri.tryParse(url.trim())?.hasScheme == true;

  Map<String, dynamic> toJson() => {
        'url': url,
        'req': requestFormat.name,
        'imageField': imageField,
        'resp': responseFormat.name,
        'responseField': responseField,
        'headers': headers,
      };

  factory OcrApiConfig.fromJson(Map<String, dynamic> j) => OcrApiConfig(
        url: j['url'] as String? ?? '',
        requestFormat: OcrRequestFormat.values.firstWhere(
          (e) => e.name == j['req'], orElse: () => OcrRequestFormat.base64Json),
        imageField: j['imageField'] as String? ?? 'image',
        responseFormat: OcrResponseFormat.values.firstWhere(
          (e) => e.name == j['resp'], orElse: () => OcrResponseFormat.jsonField),
        responseField: j['responseField'] as String? ?? 'result',
        headers: (j['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
      );

  OcrApiConfig copyWith({
    String? url,
    OcrRequestFormat? requestFormat,
    String? imageField,
    OcrResponseFormat? responseFormat,
    String? responseField,
    Map<String, String>? headers,
  }) =>
      OcrApiConfig(
        url: url ?? this.url,
        requestFormat: requestFormat ?? this.requestFormat,
        imageField: imageField ?? this.imageField,
        responseFormat: responseFormat ?? this.responseFormat,
        responseField: responseField ?? this.responseField,
        headers: headers ?? this.headers,
      );
}

class HttpOcrCaptchaSolver implements CaptchaSolver {
  HttpOcrCaptchaSolver(this.config, {Dio? dio, this.expectedLength = 4})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 8)));

  final OcrApiConfig config;
  final Dio _dio;
  final int expectedLength;

  @override
  Future<String?> solve(List<int> imageBytes) async {
    if (!config.isValid || imageBytes.isEmpty) return null;
    try {
      final Response<dynamic> resp;
      switch (config.requestFormat) {
        case OcrRequestFormat.multipart:
          final form = FormData.fromMap({
            config.imageField: MultipartFile.fromBytes(imageBytes, filename: 'captcha.png'),
          });
          resp = await _dio.post(config.url, data: form, options: Options(headers: config.headers));
        case OcrRequestFormat.base64Json:
          resp = await _dio.post(
            config.url,
            data: {config.imageField: base64.encode(imageBytes)},
            options: Options(headers: config.headers, contentType: 'application/json'),
          );
        case OcrRequestFormat.rawBytes:
          resp = await _dio.post(
            config.url,
            data: Stream.fromIterable([imageBytes]),
            options: Options(
              headers: {...config.headers, Headers.contentLengthHeader: imageBytes.length},
              contentType: 'application/octet-stream',
            ),
          );
      }
      final answer = _extract(resp.data);
      if (answer == null) return null;
      final cleaned = answer.replaceAll(RegExp(r'\s+'), '');
      if (cleaned.isEmpty) return null;
      if (expectedLength > 0 && cleaned.length != expectedLength) return null;
      return cleaned;
    } catch (_) {
      return null;
    }
  }

  String? _extract(dynamic body) {
    switch (config.responseFormat) {
      case OcrResponseFormat.plainText:
        return body?.toString();
      case OcrResponseFormat.jsonField:
        Map<String, dynamic>? map;
        if (body is Map) {
          map = body.cast<String, dynamic>();
        } else if (body is String) {
          try {
            final decoded = jsonDecode(body);
            if (decoded is Map) map = decoded.cast<String, dynamic>();
          } catch (_) {
            return null;
          }
        }
        return map?[config.responseField]?.toString();
    }
  }
}
