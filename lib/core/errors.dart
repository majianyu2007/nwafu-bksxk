/// A typed error taxonomy for the whole client.
///
/// The self-check requirement: never surface a bare "请求失败". Every failure
/// should tell the user *which* kind it is, because the remedy differs — connect
/// to the campus network, re-login, wait out maintenance, or report a schema
/// change. [AppError] classifies a failure and carries a user-facing message,
/// a remedy hint, and whether it is safe/likely to retry.
library;

import 'package:dio/dio.dart';

/// The kind of failure, ordered roughly from environment → auth → server → data.
enum AppErrorKind {
  /// No route to host / DNS failure / connection refused. On this system that
  /// usually means "not on the campus network".
  campusNetwork,

  /// Timeout — server reachable but slow, or flaky link.
  timeout,

  /// TLS/certificate problem.
  certificate,

  /// The session/token expired and automatic re-login did not succeed.
  sessionExpired,

  /// Captcha was rejected (during login/re-login).
  captcha,

  /// The account is abnormal (locked, wrong credentials, not eligible).
  account,

  /// Server returned 5xx.
  serverError,

  /// The course/class is full or otherwise not grabbable right now.
  courseFull,

  /// The batch/round is closed or not open yet.
  batchClosed,

  /// Server says it is under maintenance, or is rate-limiting us.
  maintenanceOrThrottle,

  /// We got HTML (a login/redirect page) or otherwise unparseable data where
  /// JSON was expected — often a login redirect or an interface change.
  schemaOrRedirect,

  /// A business rejection with a message we pass through verbatim.
  businessRejected,

  /// Anything we could not classify.
  unknown,
}

class AppError implements Exception {
  AppError(
    this.kind, {
    required this.message,
    this.hint,
    this.retryable = false,
    this.raw,
    this.serverCode,
  });

  final AppErrorKind kind;

  /// Short, user-facing description (Chinese).
  final String message;

  /// What the user can do about it, if anything.
  final String? hint;

  /// Whether an automated retry is sensible. The monitor uses this to decide
  /// between backing off (retryable) and hard-stopping (not retryable).
  final bool retryable;

  /// Original error/exception for diagnostics.
  final Object? raw;

  /// The server's business code, if any.
  final String? serverCode;

  /// True when the monitor MUST stop rather than keep hammering the server.
  bool get isHardStop => switch (kind) {
        AppErrorKind.captcha ||
        AppErrorKind.account ||
        AppErrorKind.maintenanceOrThrottle ||
        AppErrorKind.sessionExpired =>
          true,
        _ => false,
      };

  @override
  String toString() => 'AppError(${kind.name}): $message';

  /// Classifies a Dio transport error.
  factory AppError.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppError(
          AppErrorKind.timeout,
          message: '连接超时',
          hint: '学校服务器响应缓慢，或网络不稳定。稍后重试。',
          retryable: true,
          raw: e,
        );
      case DioExceptionType.badCertificate:
        return AppError(
          AppErrorKind.certificate,
          message: '证书验证失败',
          hint: '可能是网络中间人或代理导致。检查网络环境。',
          retryable: false,
          raw: e,
        );
      case DioExceptionType.connectionError:
        return AppError(
          AppErrorKind.campusNetwork,
          message: '无法连接到选课服务器',
          hint: '本系统仅在校园网内可用。请连接校园网，或使用 VPN 接入校园网后重试。',
          retryable: true,
          raw: e,
        );
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code >= 500) {
          return AppError(
            AppErrorKind.serverError,
            message: '服务器错误 ($code)',
            hint: '学校服务器暂时故障，稍后再试。',
            retryable: true,
            raw: e,
          );
        }
        if (code == 401 || code == 403) {
          return AppError(
            AppErrorKind.sessionExpired,
            message: '登录状态已失效',
            hint: '请重新登录。',
            retryable: false,
            raw: e,
          );
        }
        return AppError(
          AppErrorKind.unknown,
          message: '请求被拒绝 ($code)',
          retryable: false,
          raw: e,
        );
      case DioExceptionType.cancel:
        return AppError(AppErrorKind.unknown, message: '请求已取消', raw: e);
      default:
        // Includes DioExceptionType.unknown and any future types.
        // On web, CORS shows up here.
        final msg = e.message ?? '';
        if (msg.contains('XMLHttpRequest') || msg.toLowerCase().contains('cors')) {
          return AppError(
            AppErrorKind.campusNetwork,
            message: '浏览器无法直接访问选课服务器',
            hint: '网页版受跨域限制。请安装配套的浏览器脚本，或使用桌面/移动端。',
            retryable: false,
            raw: e,
          );
        }
        return AppError(
          AppErrorKind.campusNetwork,
          message: '网络请求失败',
          hint: '确认已连接校园网后重试。',
          retryable: true,
          raw: e,
        );
    }
  }

  /// Classifies a business-level response (code != "1") by its message text.
  factory AppError.fromBusiness(String code, String msg, {Object? raw}) {
    final m = msg;
    bool has(List<String> keys) => keys.any(m.contains);

    if (has(['验证码'])) {
      return AppError(AppErrorKind.captcha,
          message: msg.isEmpty ? '验证码错误' : msg, hint: '刷新验证码后重试。', serverCode: code, raw: raw);
    }
    if (has(['密码', '账号', '学号', '不存在', '锁定', '冻结', '无权限', '不允许'])) {
      return AppError(AppErrorKind.account,
          message: msg, hint: '检查账号密码或选课资格。', serverCode: code, raw: raw);
    }
    if (has(['维护', '繁忙', '频繁', '限流', '稍后', '拥挤', '排队'])) {
      return AppError(AppErrorKind.maintenanceOrThrottle,
          message: msg, hint: '系统繁忙或维护中，已暂停自动操作以免加重负载。', retryable: false, serverCode: code, raw: raw);
    }
    if (has(['已满', '容量', '名额', '满员'])) {
      return AppError(AppErrorKind.courseFull,
          message: msg.isEmpty ? '名额已满' : msg, retryable: true, serverCode: code, raw: raw);
    }
    if (has(['未开放', '不在选课', '已结束', '轮次', '时间'])) {
      return AppError(AppErrorKind.batchClosed,
          message: msg, hint: '当前选课轮次未开放或已结束。', retryable: false, serverCode: code, raw: raw);
    }
    if (has(['登录', 'token', '会话', '超时', '重新登录'])) {
      return AppError(AppErrorKind.sessionExpired,
          message: msg.isEmpty ? '登录状态已失效' : msg, hint: '请重新登录。', serverCode: code, raw: raw);
    }
    return AppError(AppErrorKind.businessRejected,
        message: msg.isEmpty ? '操作未成功 (code=$code)' : msg, serverCode: code, raw: raw);
  }

  /// Classifies an HTML/non-JSON body where JSON was expected.
  factory AppError.schema(String detail) => AppError(
        AppErrorKind.schemaOrRedirect,
        message: '返回了非预期的内容',
        hint: '可能是登录已过期被重定向，或学校接口发生变化。请重新登录；若持续出现请在诊断页导出日志反馈。',
        retryable: false,
        raw: detail,
      );
}
