import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pub_semver/pub_semver.dart';

import '../core/update_links.dart';

/// SemVer precedence ignores build metadata (unlike pub's package ordering).
Version? parseUpdateVersion(String value) {
  final normalized = value.trim().replaceFirst(RegExp(r'^v'), '');
  if (!RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
  ).hasMatch(normalized)) {
    return null;
  }
  try {
    final parsed = Version.parse(normalized);
    return Version(
      parsed.major,
      parsed.minor,
      parsed.patch,
      pre: parsed.preRelease.isEmpty ? null : parsed.preRelease.join('.'),
    );
  } on FormatException {
    return null;
  }
}

bool isNewerStableVersion(String candidate, String installed) {
  final latest = parseUpdateVersion(candidate);
  final current = parseUpdateVersion(installed);
  return latest != null &&
      current != null &&
      latest.preRelease.isEmpty &&
      latest > current;
}

enum UpdateStatus { idle, checking, available, current, unavailable, error }

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.url,
    required this.name,
    this.notes = '',
    this.publishedAt,
  });

  final String version;
  final Uri url;
  final String name;
  final String notes;
  final DateTime? publishedAt;
}

class UpdateCheck {
  const UpdateCheck({
    this.status = UpdateStatus.idle,
    this.currentVersion,
    this.release,
    this.message = '尚未检查',
  });

  final UpdateStatus status;
  final String? currentVersion;
  final UpdateRelease? release;
  final String message;

  bool get hasUpdate => status == UpdateStatus.available;

  UpdateCheck checking() => UpdateCheck(
        status: UpdateStatus.checking,
        currentVersion: currentVersion,
        release: release,
        message: '正在检查…',
      );
}

/// A private, session-less HTTP client: no ApiClient, token, cookie jar,
/// interceptors or school-server origin. Inject only an adapter for tests.
class UpdateService {
  UpdateService({HttpClientAdapter? adapter})
      : _http = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          responseType: ResponseType.plain,
          followRedirects: false,
          headers: {'Accept': 'application/json, text/plain'},
        )) {
    if (adapter != null) _http.httpClientAdapter = adapter;
  }

  final Dio _http;
  static final _latestReleaseUri = Uri.https(
    'api.github.com',
    '/repos/majianyu2007/nwafu-bksxk/releases/latest',
  );
  static final _webVersionUri =
      Uri.https('mjy.js.org', '/nwafu-bksxk/app/version.json');

  void dispose() => _http.close(force: true);

  Future<String> _read(Uri uri, {bool bustCache = false}) async {
    final target = bustCache
        ? uri.replace(queryParameters: {
            '_check': DateTime.now().millisecondsSinceEpoch.toString(),
          })
        : uri;
    final response = await _http.getUri<String>(target);
    if (response.statusCode != 200 || response.data == null) {
      throw const FormatException('Invalid update response');
    }
    return response.data!;
  }

  Future<UpdateCheck> checkApp({
    required String currentVersion,
    required bool isWeb,
  }) async {
    if (parseUpdateVersion(currentVersion) == null) {
      return UpdateCheck(
        status: UpdateStatus.unavailable,
        currentVersion: currentVersion,
        message: '无法识别当前版本，请打开官方发布页查看。',
      );
    }
    try {
      final data = jsonDecode(await _read(
        isWeb ? _webVersionUri : _latestReleaseUri,
        bustCache: isWeb,
      ));
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid update metadata');
      }
      final rawVersion = data[isWeb ? 'version' : 'tag_name'];
      final version =
          rawVersion is String ? parseUpdateVersion(rawVersion) : null;
      if (version == null) {
        throw const FormatException('Invalid release version');
      }
      if (version.preRelease.isNotEmpty ||
          (!isWeb && (data['prerelease'] == true || data['draft'] == true))) {
        return UpdateCheck(
          status: UpdateStatus.unavailable,
          currentVersion: currentVersion,
          message: '发布源暂无可用的稳定版；不会提示安装预发布版本。',
        );
      }
      final uri = isWeb
          ? webAppUri
          : Uri(
              scheme: 'https',
              host: 'github.com',
              pathSegments: [
                'majianyu2007',
                'nwafu-bksxk',
                'releases',
                'tag',
                (rawVersion as String).trim(),
              ],
            );
      if (!isOfficialUpdateLink(uri)) {
        throw const FormatException('Invalid release destination');
      }
      return _compare(
        currentVersion,
        UpdateRelease(
          version: version.toString(),
          url: uri,
          name: isWeb ? '网页版 ${version.toString()}' : _text(data['name']),
          notes: isWeb ? '' : _text(data['body']),
          publishedAt: DateTime.tryParse(_text(data['published_at'])),
        ),
      );
    } catch (error) {
      return _failure(currentVersion, error);
    }
  }

  Future<UpdateCheck> checkBridge({
    required bool isWeb,
    required bool installed,
    required String? currentVersion,
  }) async {
    if (!isWeb) {
      return const UpdateCheck(
        status: UpdateStatus.unavailable,
        message: '原生应用不需要桥接脚本；仅浏览器网页版使用。',
      );
    }
    if (!installed) {
      return const UpdateCheck(
        status: UpdateStatus.unavailable,
        message: '未检测到桥接脚本，请先安装并刷新网页版。',
      );
    }
    if (currentVersion == null || parseUpdateVersion(currentVersion) == null) {
      return UpdateCheck(
        status: UpdateStatus.unavailable,
        currentVersion: currentVersion,
        message: '已检测到桥接，但脚本未提供有效版本；请打开安装页核对。',
      );
    }
    try {
      // Read the already-deployed userscript metadata; no new manifest or
      // unpublished GitHub release is required to check bridge updates.
      final script = await _read(bridgeInstallerUri, bustCache: true);
      final header = RegExp(
        r'// ==UserScript==([\s\S]*?)// ==/UserScript==',
      ).firstMatch(script)?.group(1);
      final candidate = header == null
          ? null
          : RegExp(r'^//\s*@version\s+(\S+)\s*$', multiLine: true)
              .firstMatch(header)
              ?.group(1);
      final version = candidate == null ? null : parseUpdateVersion(candidate);
      if (version == null) {
        throw const FormatException('Invalid script version');
      }
      if (version.preRelease.isNotEmpty) {
        return UpdateCheck(
          status: UpdateStatus.unavailable,
          currentVersion: currentVersion,
          message: '脚本发布源暂无可用的稳定版。',
        );
      }
      return _compare(
        currentVersion,
        UpdateRelease(
          version: version.toString(),
          url: bridgeInstallerUri,
          name: 'Web 跨域桥接 ${version.toString()}',
        ),
      );
    } catch (error) {
      return _failure(currentVersion, error);
    }
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static UpdateCheck _compare(String current, UpdateRelease release) {
    final newer = isNewerStableVersion(release.version, current);
    return UpdateCheck(
      status: newer ? UpdateStatus.available : UpdateStatus.current,
      currentVersion: current,
      release: release,
      message: newer ? '发现新版本 ${release.version}' : '当前版本无需更新',
    );
  }

  static UpdateCheck _failure(String current, Object error) {
    var message = '检查失败，请检查网络后重试；不影响选课和监控。';
    if (error is FormatException) {
      message = '更新信息格式异常，请稍后重试或查看官方发布页。';
    } else if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 403 || status == 429) {
        message = '更新服务暂时限流，请稍后重试。';
      } else if (status == 404) {
        message = '发布源暂无可用的版本信息，请稍后重试。';
      }
    }
    return UpdateCheck(
      status: UpdateStatus.error,
      currentVersion: current,
      message: message,
    );
  }
}
