/// 图书馆空间预约 (booking-lib.nwafu.edu.cn): free seats and seminar rooms,
/// native seat booking, sign-in/leave/checkout/renew/cancel, the student's
/// bookings and the library entrance QR code.
///
/// Sign-in rides on the unified identity: `GET /api/cas/cas` goes through
/// the AuthServer and lands on `/h5/index.html#/cas/?cas=<code>`; `POST
/// /api/cas/user {cas}` trades the code for a bearer token, which every call
/// then carries both as the `authorization` header and in the JSON body.
///
/// Sensitive write endpoints (`/api/Seat/confirm`, `/api/seat/xuzuoconfirm`)
/// send their JSON body encrypted as `aesjson` via [encryptLibraryPayload].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/crypto/library_crypto.dart';
import '../core/errors.dart';
import '../core/web_env.dart';
import 'cas_client.dart';

const kLibraryOrigin = 'https://booking-lib.nwafu.edu.cn';

/// The official H5 page, for the actions the app leaves to it.
Uri libraryPage([String route = '/home']) =>
    Uri.parse('$kLibraryOrigin/h5/index.html#$route');

/// 选座 (id 1) or 空间服务 (研讨室 etc., id 2).
enum LibraryKind {
  seat('1', '座位'),
  space('2', '研讨室');

  const LibraryKind(this.id, this.label);
  final String id;
  final String label;
}

/// One bookable area: a reading area of seats, or a seminar room.
class LibraryArea {
  const LibraryArea({
    required this.id,
    this.parentId = '',
    required this.name,
    required this.campus,
    required this.floor,
    required this.typeName,
    this.total,
    this.free,
    this.capacity,
    this.fullyBooked = false,
    this.description = '',
    this.imageUrl = '',
  });

  factory LibraryArea.fromJson(Map<String, dynamic> j) {
    int? n(Object? v) => v == null ? null : int.tryParse('$v');
    final merge = '${j['nameMerge'] ?? ''}'.split('-');
    final rawImg =
        '${j['firstimg'] ?? j['thumb_img'] ?? j['top_img'] ?? j['img'] ?? j['image'] ?? ''}'
            .trim();
    return LibraryArea(
      id: '${j['id']}',
      parentId: '${j['parentId'] ?? j['parent_id'] ?? j['area'] ?? ''}',
      name: '${j['name'] ?? ''}',
      campus: '${j['premisesName'] ?? (merge.isNotEmpty ? merge.first : '')}',
      floor: '${j['storeyName'] ?? (merge.length > 1 ? merge[1] : '')}',
      typeName: '${j['type_name'] ?? ''}',
      total: n(j['total_num']),
      free: n(j['free_num']),
      capacity: n(j['maxPerson']),
      fullyBooked: '${j['Fully_Booked'] ?? '0'}' == '1',
      description: '${j['sub_title'] ?? ''}'.trim(),
      imageUrl: LibrarySeatMap._resolveUrl(rawImg),
    );
  }

  final String id;
  final String parentId;
  final String name;
  final String campus;
  final String floor;
  final String typeName;

  /// Seats: how many in total and free now.
  final int? total;
  final int? free;

  /// Seminar rooms: how many people fit.
  final int? capacity;
  final bool fullyBooked;
  final String description;
  final String imageUrl;
}

/// A bookable time slot within a day (`/api/Seat/date` → `times[]`).
class LibraryTimeSlot {
  const LibraryTimeSlot({
    required this.id,
    required this.start,
    required this.end,
  });

  factory LibraryTimeSlot.fromJson(Map<String, dynamic> j) => LibraryTimeSlot(
    id: '${j['id'] ?? ''}',
    start: '${j['start'] ?? ''}',
    end: '${j['end'] ?? ''}',
  );

  final String id;
  final String start;
  final String end;

  String get label => '$start–$end';
}

/// One bookable date and its available time slots.
class LibraryBookDate {
  const LibraryBookDate({required this.day, required this.times});

  factory LibraryBookDate.fromJson(Map<String, dynamic> j) {
    final raw = j['times'];
    return LibraryBookDate(
      day: '${j['day'] ?? ''}',
      times: raw is List
          ? raw
                .whereType<Map<String, dynamic>>()
                .map(LibraryTimeSlot.fromJson)
                .where((t) => t.id.isNotEmpty)
                .toList()
          : const [],
    );
  }

  final String day;
  final List<LibraryTimeSlot> times;
}

/// Floorplan image URLs for a reading area (`/api/seat/map`).
class LibrarySeatMap {
  const LibrarySeatMap({
    required this.freeUrl,
    this.bookUrl = '',
    this.useUrl = '',
    this.leaveUrl = '',
    this.closeUrl = '',
  });

  factory LibrarySeatMap.fromJson(Map<String, dynamic> j) => LibrarySeatMap(
    freeUrl: _resolveUrl(
      '${j['free'] ?? j['img'] ?? j['map'] ?? j['thumb_img'] ?? j['background'] ?? ''}',
    ),
    bookUrl: _resolveUrl('${j['book'] ?? ''}'),
    useUrl: _resolveUrl('${j['use'] ?? ''}'),
    leaveUrl: _resolveUrl('${j['leave'] ?? ''}'),
    closeUrl: _resolveUrl('${j['close'] ?? ''}'),
  );

  static String _resolveUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return s.startsWith('/') ? '$kLibraryOrigin$s' : '$kLibraryOrigin/$s';
  }

  final String freeUrl;
  final String bookUrl;
  final String useUrl;
  final String leaveUrl;
  final String closeUrl;

  bool get hasImage => freeUrl.isNotEmpty;
}

/// Visual status of an individual library seat.
enum LibrarySeatStatus { free, leave, booked, inUse, closed }

/// One individual seat in a reading area (`/api/Seat/seat`), including its
/// percentage position (`0..100`) on the floorplan image.
class LibrarySeat {
  const LibrarySeat({
    required this.id,
    required this.no,
    required this.name,
    required this.status,
    required this.statusName,
    this.pointX,
    this.pointY,
    this.width,
    this.height,
    this.inLabel = true,
  });

  factory LibrarySeat.fromJson(Map<String, dynamic> j) {
    double? d(Object? v) {
      if (v == null) return null;
      final cleaned = '$v'.replaceAll('%', '').trim();
      return double.tryParse(cleaned);
    }

    final inLabelRaw = j['in_label'];
    return LibrarySeat(
      id: '${j['id'] ?? ''}',
      no: '${j['no'] ?? j['name'] ?? ''}',
      name: '${j['name'] ?? j['no'] ?? ''}',
      status: '${j['status'] ?? ''}',
      statusName: '${j['status_name'] ?? j['statusName'] ?? ''}',
      pointX: d(j['point_x'] ?? j['pointX'] ?? j['x']),
      pointY: d(j['point_y'] ?? j['pointY'] ?? j['y']),
      width: d(j['width'] ?? j['w']),
      height: d(j['height'] ?? j['h']),
      inLabel: inLabelRaw == null || '$inLabelRaw' == '1' || inLabelRaw == true,
    );
  }

  final String id;
  final String no;
  final String name;
  final String status;
  final String statusName;

  /// Percentage coordinates (`0..100`) on the area's floorplan image.
  final double? pointX;
  final double? pointY;
  final double? width;
  final double? height;
  final bool inLabel;

  bool get hasCoords =>
      pointX != null &&
      pointY != null &&
      width != null &&
      height != null &&
      width! > 0 &&
      height! > 0;

  /// `status == "1"` indicates a free/bookable seat in the official H5 app.
  bool get isFree =>
      inLabel && (status == '1' || statusName == '空闲' || statusName == '可预约');

  LibrarySeatStatus get visualStatus {
    if (!inLabel) return LibrarySeatStatus.closed;
    if (isFree) return LibrarySeatStatus.free;
    if (status == '7') return LibrarySeatStatus.leave;
    if (status == '2' || status == '10' || status == '11') {
      return LibrarySeatStatus.booked;
    }
    if (status == '6' || status == '8' || status == '9') {
      return LibrarySeatStatus.inUse;
    }
    return LibrarySeatStatus.closed;
  }
}

/// A seminar room teammate returned by `/api/Seminar/group`.
class LibraryTeamMember {
  const LibraryTeamMember({
    required this.id,
    required this.name,
    required this.card,
  });

  factory LibraryTeamMember.fromJson(Map<String, dynamic> j) =>
      LibraryTeamMember(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? j['realname'] ?? ''}',
        card: '${j['card'] ?? j['username'] ?? ''}',
      );

  final String id;
  final String name;
  final String card;
}

/// Bookable schedule info for a seminar room on one day (`/api/Seminar/seminar`).
class LibrarySeminarDay {
  const LibrarySeminarDay({
    required this.day,
    required this.minPerson,
    required this.maxPerson,
    required this.openStart,
    required this.openEnd,
    this.bookedRanges = const [],
    this.minDurationMinutes = 60,
    this.maxDurationMinutes = 240,
  });

  factory LibrarySeminarDay.fromJson(String day, Map<String, dynamic> j) {
    int n(Object? v, int fallback) => int.tryParse('${v ?? ''}') ?? fallback;
    final booked = <(String, String)>[];
    final rawList = j['list'] ?? j['booked'] ?? j['books'];
    if (rawList is List) {
      for (final item in rawList.whereType<Map<String, dynamic>>()) {
        final s = '${item['start_time'] ?? item['start'] ?? ''}'.trim();
        final e = '${item['end_time'] ?? item['end'] ?? ''}'.trim();
        if (s.isNotEmpty && e.isNotEmpty) booked.add((s, e));
      }
    }
    final openStart =
        '${j['start_time'] ?? j['open_start'] ?? j['begin'] ?? '08:00'}'.trim();
    final openEnd =
        '${j['end_time'] ?? j['open_end'] ?? j['end'] ?? '22:00'}'.trim();
    return LibrarySeminarDay(
      day: day,
      minPerson: n(j['minPerson'] ?? j['min_person'], 1),
      maxPerson: n(j['maxPerson'] ?? j['max_person'], 8),
      openStart: openStart.isEmpty ? '08:00' : openStart,
      openEnd: openEnd.isEmpty ? '22:00' : openEnd,
      bookedRanges: booked,
      minDurationMinutes: n(j['min_time'], 60),
      maxDurationMinutes: n(j['max_time'], 240),
    );
  }

  final String day;
  final int minPerson;
  final int maxPerson;
  final String openStart;
  final String openEnd;
  final List<(String, String)> bookedRanges;
  final int minDurationMinutes;
  final int maxDurationMinutes;
}

/// A booking of the student's (seat or room).
class LibraryBooking {
  const LibraryBooking({
    required this.id,
    required this.place,
    required this.seat,
    required this.day,
    required this.start,
    required this.end,
    required this.status,
    required this.statusName,
    this.begin,
    this.spaceId = '',
    this.isRoom = false,
    this.xuzuoSegment = '',
  });

  factory LibraryBooking.fromJson(
    Map<String, dynamic> j, {
    bool isRoom = false,
  }) => LibraryBooking(
    id: '${j['id']}',
    place: '${j['nameMerge'] ?? j['areaName'] ?? ''}',
    seat: '${j['no'] ?? j['name'] ?? ''}',
    day: '${j['day'] ?? ''}',
    start: '${j['start'] ?? ''}',
    end: '${j['end'] ?? ''}',
    status: '${j['status'] ?? ''}',
    statusName: '${j['statusName'] ?? ''}',
    begin: DateTime.tryParse('${j['beginTime'] ?? ''}'.replaceFirst(' ', 'T')),
    spaceId: '${j['space_id'] ?? j['seat_id'] ?? ''}',
    isRoom: isRoom,
    xuzuoSegment: '${j['xuzuosegment'] ?? ''}',
  );

  final String id;
  final String place;
  final String seat;
  final String day;
  final String start;
  final String end;
  final String status;
  final String statusName;
  final DateTime? begin;
  final String spaceId;
  final bool isRoom;
  final String xuzuoSegment;

  /// Still to come or in use (not 已结束 / 已取消 / 违约).
  bool get active =>
      !const {'已结束', '已取消', '已违约', '违约', '已完成'}.contains(statusName);

  bool get canSignIn =>
      active &&
      (statusName.contains('待签到') ||
          statusName.contains('预约成功') ||
          statusName.contains('暂离'));

  bool get canLeave => active && statusName.contains('使用中');

  bool get canCheckout =>
      active && (statusName.contains('使用中') || statusName.contains('暂离'));

  bool get canCancel =>
      active &&
      (statusName.contains('预约') || statusName.contains('待签到'));

  bool get canRenew =>
      active && !isRoom && spaceId.isNotEmpty && xuzuoSegment.isNotEmpty;
}

class LibraryMember {
  const LibraryMember({
    required this.name,
    required this.roleName,
    this.qrImage,
  });
  final String name;
  final String roleName;

  /// `data:image/png;base64,…` of the entrance QR code.
  final String? qrImage;
}

class LibraryService {
  LibraryService(this.cas, {this.onLoginRequired});
  final CasClient cas;

  /// Signs the unified identity in again when its session has lapsed (the
  /// same silent re-login the EMAP apps use).
  final Future<bool> Function()? onLoginRequired;
  String? _token;
  Future<String>? _loginInFlight;

  Dio get _dio => cas.dio;

  static void _requireBridgeOnWeb() {
    if (kIsWeb && !isFullCampusBridgeReady) {
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '请更新网页版桥接脚本（需 ≥ 1.4.2）',
        hint: '旧版桥接脚本不支持楼层平面图加载和研讨室预约接口，请点击更新脚本后刷新页面。',
      );
    }
  }

  Future<String> _login({bool retried = false}) {
    if (!retried && _loginInFlight != null) return _loginInFlight!;
    final future = _doLogin(retried: retried);
    if (!retried) {
      _loginInFlight = future.whenComplete(() => _loginInFlight = null);
      return _loginInFlight!;
    }
    return future;
  }

  Future<String> _doLogin({bool retried = false}) async {
    _requireBridgeOnWeb();
    final res = await cas.follow('$kLibraryOrigin/api/cas/cas');
    if (res.realUri.host == Uri.parse(kAuthServer).host && !retried) {
      // The AuthServer wants a login: the unified session has expired.
      if (!kIsWeb && await (onLoginRequired?.call() ?? Future.value(false))) {
        return _doLogin(retried: true);
      }
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '统一身份认证未登录或已过期',
        hint: kIsWeb
            ? '请先在浏览器打开学校统一身份认证页面登录，再回来刷新。'
            : '请重新登录后再试。',
      );
    }
    final fragment = res.realUri.fragment;
    final code =
        Uri.tryParse(
          fragment.startsWith('/') ? 'x:$fragment' : 'x:/$fragment',
        )?.queryParameters['cas'] ??
        res.realUri.queryParameters['cas'];
    if (code == null || code.isEmpty) {
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '图书馆登录没有完成',
        hint: kIsWeb
            ? '请先在浏览器打开 booking-lib.nwafu.edu.cn 完成一次登录后再刷新。'
            : '统一身份认证可能已过期，请重新登录后再试。',
      );
    }
    final r = await _post('/api/cas/user', {'cas': code}, auth: false);
    final token = (r['member'] as Map?)?['token']?.toString();
    if (token == null || token.isEmpty) {
      throw AppError(AppErrorKind.unknown, message: '图书馆没有返回登录凭证');
    }
    return _token = token;
  }

  static Map<String, dynamic>? _decodeMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
    bool encrypted = false,
    bool retried = false,
  }) async {
    _requireBridgeOnWeb();
    final token = auth ? (_token ?? await _login()) : null;
    final payload = encrypted
        ? <String, dynamic>{'aesjson': encryptLibraryPayload(body)}
        : body;
    final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        '$kLibraryOrigin$path',
        data: {...payload, if (token != null) 'authorization': 'bearer$token'},
        options: Options(
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'lang': 'zh',
            if (token != null) 'authorization': 'bearer$token',
          },
        ),
      );
    } on DioException catch (e) {
      throw AppError(
        AppErrorKind.campusNetwork,
        message: '连接图书馆系统失败',
        hint: '请确认已连接校园网或校外访问，然后重试。',
        retryable: true,
        raw: e,
      );
    }
    final data = _decodeMap(res.data);
    if (data == null) {
      final text = res.data is String ? (res.data as String) : '';
      if (text.contains('authserver') ||
          text.contains('<form') ||
          res.statusCode == 302 ||
          res.statusCode == 401) {
        if (auth && !retried) {
          _token = null;
          return _post(path, body, encrypted: encrypted, retried: true);
        }
        throw AppError(
          AppErrorKind.sessionExpired,
          message: '图书馆登录状态已失效',
          hint: '请重新登录后重试。',
        );
      }
      throw AppError(
        AppErrorKind.schemaOrRedirect,
        message: '图书馆系统返回了无法识别的内容',
        hint: '状态码 ${res.statusCode ?? 0}，请稍后重试。',
      );
    }
    final code = '${data['code']}';
    if (code == '10001' && auth && !retried) {
      _token = null;
      return _post(path, body, encrypted: encrypted, retried: true);
    }
    // /api/* answers code 1 on success, /reserve/* answers 0.
    if (code != '1' && code != '0') {
      throw AppError(
        AppErrorKind.unknown,
        message: '${data['msg'] ?? data['message'] ?? '图书馆系统暂时不可用'}',
      );
    }
    return data;
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Bookable areas of [kind] on [date], with live free counts for seats.
  Future<List<LibraryArea>> areas(LibraryKind kind, DateTime date) async {
    final out = <LibraryArea>[];
    for (var page = 1; page <= 10; page++) {
      final r = await _post('/reserve/index/list', {
        'id': kind.id,
        'date': _day(date),
        'members': 0,
        'size': 50,
        'page': page,
      });
      final d = r['data'];
      final list = d is Map ? d['list'] : null;
      if (list is! List) break;
      out.addAll(
        list.whereType<Map<String, dynamic>>().map(LibraryArea.fromJson),
      );
      final pages = d is Map ? int.tryParse('${d['totalPage'] ?? ''}') : null;
      if (list.length < 50 || (pages != null && page >= pages)) break;
    }
    return out;
  }

  /// The student's seat bookings, newest first.
  Future<List<LibraryBooking>> seatBookings({int page = 1}) async {
    final r = await _post('/api/Member/seat', {'page': page, 'limit': 20});
    final d = r['data'];
    final list = d is Map ? d['data'] : null;
    return list is List
        ? list
              .whereType<Map<String, dynamic>>()
              .map(LibraryBooking.fromJson)
              .toList()
        : const [];
  }

  /// The student's room (研讨室 / 空间) bookings, newest first.
  Future<List<LibraryBooking>> roomBookings({int page = 1}) async {
    final r = await _post('/api/Member/seminar', {'page': page, 'limit': 20});
    final d = r['data'];
    final list = d is Map ? d['data'] : (d is List ? d : null);
    return list is List
        ? list
              .whereType<Map<String, dynamic>>()
              .map((j) => LibraryBooking.fromJson(j, isRoom: true))
              .toList()
        : const [];
  }

  /// Bookable dates and time slots for a seat reading area.
  Future<List<LibraryBookDate>> seatDates(String areaId) async {
    final r = await _post('/api/Seat/date', {'build_id': areaId});
    final d = r['data'];
    return d is List
        ? d
              .whereType<Map<String, dynamic>>()
              .map(LibraryBookDate.fromJson)
              .where((x) => x.day.isNotEmpty)
              .toList()
        : const [];
  }

  /// All seats in [areaId] for [day] and [slot].
  Future<List<LibrarySeat>> seats(
    String areaId, {
    required String day,
    required LibraryTimeSlot slot,
  }) async {
    final r = await _post('/api/Seat/seat', {
      'area': areaId,
      'segment': slot.id,
      'day': day,
      'startTime': slot.start,
      'endTime': slot.end,
    });
    final d = r['data'];
    return d is List
        ? d
              .whereType<Map<String, dynamic>>()
              .map(LibrarySeat.fromJson)
              .where((s) => s.id.isNotEmpty)
              .toList()
        : const [];
  }

  /// Floorplan reference image URLs for a reading area (`/api/seat/map`).
  Future<LibrarySeatMap?> seatMap(String areaId) async {
    final r = await _post('/api/seat/map', {'id': areaId});
    final d = r['data'];
    if (d is Map<String, dynamic>) {
      final map = LibrarySeatMap.fromJson(d);
      return map.hasImage ? map : null;
    }
    return null;
  }

  /// Downloads a floorplan image via Dio (so Web uses the GM bridge without
  /// CanvasKit CORS errors, and native uses CampusProxy VPN off-campus).
  Future<Uint8List> fetchImageBytes(String url) async {
    _requireBridgeOnWeb();
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      final data = res.data;
      if (data == null || data.isEmpty) {
        throw AppError(AppErrorKind.unknown, message: '楼层参考图内容为空');
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      throw AppError(
        AppErrorKind.campusNetwork,
        message: '加载楼层参考图失败',
        raw: e,
      );
    }
  }

  static bool _isFatalLibraryError(Object e) =>
      e is AppError &&
      (e.kind == AppErrorKind.sessionExpired ||
          e.kind == AppErrorKind.campusNetwork ||
          e.kind == AppErrorKind.schemaOrRedirect);

  /// Bookable dates for a seminar room: tries `/api/Seminar/date`, and falls
  /// back to `/api/Room/detail` (v2 seminar room flow used by NWAFU, reading
  /// `list[].date` with `status == 0` or `startDate`..`endDate`).
  Future<List<String>> seminarDates(String roomId) async {
    _requireBridgeOnWeb();
    try {
      final r = await _post('/api/Seminar/date', {'build_id': roomId});
      final d = r['data'];
      if (d is List) {
        final list = d
            .map((e) => e is Map ? '${e['day'] ?? e['date'] ?? ''}' : '$e')
            .map((s) => s.trim())
            .where((s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s))
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      if (_isFatalLibraryError(e)) rethrow;
      // Fall through to v2 /api/Room/detail.
    }
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final months = <String>[
      '${now.year}-${now.month.toString().padLeft(2, '0')}',
      if (now.day >= 22) () {
        final next = DateTime(now.year, now.month + 1, 1);
        return '${next.year}-${next.month.toString().padLeft(2, '0')}';
      }(),
    ];
    final found = <String>{};
    for (final month in months) {
      try {
        final r = await _post('/api/Room/detail', {
          'area_id': roomId,
          'month': month,
        });
        final d = r['data'];
        if (d is Map<String, dynamic>) {
          final rawDays = d['list'] ?? d['days'] ?? d['date'] ?? d['dateList'];
          if (rawDays is List) {
            for (final item in rawDays) {
              if (item is Map) {
                final status = '${item['status'] ?? '0'}';
                if (status != '0' && status != '1') continue;
                final s = '${item['date'] ?? item['day'] ?? ''}'.trim();
                if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) found.add(s);
              } else {
                final s = '$item'.trim();
                if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) found.add(s);
              }
            }
          }
          if (found.isEmpty) {
            final start = DateTime.tryParse('${d['startDate'] ?? ''}');
            final end = DateTime.tryParse('${d['endDate'] ?? ''}');
            if (start != null && end != null && !end.isBefore(start)) {
              final days = end.difference(start).inDays.clamp(0, 14);
              for (var i = 0; i <= days; i++) {
                found.add(_day(start.add(Duration(days: i))));
              }
            }
          }
        }
      } catch (e) {
        if (_isFatalLibraryError(e)) rethrow;
      }
    }
    if (found.isNotEmpty) {
      final todayStr = _day(now);
      final sorted = found.where((d) => d.compareTo(todayStr) >= 0).toList()
        ..sort();
      if (sorted.isNotEmpty) return sorted;
    }
    return [for (var i = 0; i < 7; i++) _day(now.add(Duration(days: i)))];
  }

  /// Schedule and capacity constraints for a seminar room on [day].
  /// Tries `/api/Seminar/seminar` and falls back to `/api/Room/detail`.
  Future<LibrarySeminarDay> seminarDay({
    required String roomId,
    required String areaId,
    required String day,
  }) async {
    _requireBridgeOnWeb();
    try {
      final r = await _post('/api/Seminar/seminar', {
        'room': roomId,
        'area': areaId,
        'day': day,
      });
      final d = r['data'];
      if (d is Map<String, dynamic> && d.isNotEmpty) {
        return LibrarySeminarDay.fromJson(day, d);
      }
    } catch (e) {
      if (_isFatalLibraryError(e)) rethrow;
      // Fall back to /api/Room/detail (v2 flow).
    }
    final month = day.length >= 7 ? day.substring(0, 7) : day;
    final r = await _post('/api/Room/detail', {
      'area_id': roomId,
      'month': month,
    });
    final d = r['data'];
    if (d is Map<String, dynamic>) {
      // In `/api/Room/detail`, `list` is the monthly calendar `[{date, status}]`,
      // NOT daily booked time ranges — remove it unless items actually look
      // like time-range slots.
      final cleaned = Map<String, dynamic>.from(d);
      final rawList = cleaned['list'];
      if (rawList is List &&
          rawList.isNotEmpty &&
          rawList.first is Map &&
          (rawList.first as Map).containsKey('date') &&
          !(rawList.first as Map).containsKey('start_time')) {
        cleaned.remove('list');
      }
      return LibrarySeminarDay.fromJson(day, {
        ...cleaned,
        'start_time': d['spaceOpenTime'] ?? d['start_time'] ?? '08:00',
        'end_time': d['spaceCloseTime'] ?? d['end_time'] ?? '22:00',
        'min_time': d['minTime'] ?? d['min_time'] ?? 60,
        'max_time': d['maxTime'] ?? d['max_time'] ?? 240,
      });
    }
    return LibrarySeminarDay.fromJson(day, const {});
  }

  /// Looks up a teammate by student card/id (`/api/Seminar/group`).
  Future<LibraryTeamMember> lookupSeminarMember({
    required String card,
    String? areaId,
    String? beginTime,
    String? endTime,
  }) async {
    final r = await _post('/api/Seminar/group', {
      'card': card.trim(),
      if (areaId != null && areaId.isNotEmpty) 'area': areaId,
      if (beginTime != null && beginTime.isNotEmpty) 'beginTime': beginTime,
      if (endTime != null && endTime.isNotEmpty) 'endTime': endTime,
    });
    final d = r['data'];
    if (d is! Map<String, dynamic> || '${d['id'] ?? ''}'.isEmpty) {
      throw AppError(AppErrorKind.unknown, message: '未找到该学号对应的同学');
    }
    return LibraryTeamMember.fromJson(d);
  }

  /// Books a seminar room natively (`/reserve/index/confirm`, AES-encrypted).
  Future<String> bookSeminar({
    required String roomId,
    required String day,
    required String startTime,
    required String endTime,
    required String title,
    required String content,
    required String mobile,
    List<String> teamUserIds = const [],
    bool isOpen = true,
  }) async {
    final body = <String, dynamic>{
      'day': day,
      'start_time': startTime,
      'end_time': endTime,
      'title': title.trim(),
      'content': content.trim(),
      'mobile': mobile.trim(),
      'room': roomId,
      'open': isOpen ? '1' : '0',
      'file_name': '',
      'file_url': '',
      if (teamUserIds.isNotEmpty) 'teamusers': teamUserIds.join(','),
    };
    final r = await _post('/reserve/index/confirm', body, encrypted: true);
    final msg = '${r['msg'] ?? r['message'] ?? ''}'.trim();
    return msg.isEmpty ? '研讨室预约成功' : msg;
  }

  /// Books a seat natively (AES-encrypted payload). Returns server message.
  Future<String> bookSeat({
    required String seatId,
    required String segmentId,
  }) async {
    final r = await _post(
      '/api/Seat/confirm',
      {'seat_id': seatId, 'segment': segmentId},
      encrypted: true,
    );
    final msg = '${r['msg'] ?? r['message'] ?? ''}'.trim();
    return msg.isEmpty ? '预约成功' : msg;
  }

  /// Signs in to an active booking.
  Future<String> signInBooking(String bookingId) async {
    final r = await _post('/api/Space/signin', {'id': bookingId});
    final msg = '${r['msg'] ?? r['message'] ?? ''}'.trim();
    return msg.isEmpty ? '签到成功' : msg;
  }

  /// Marks an in-use booking as temporarily away (暂离).
  Future<String> leaveBooking(String bookingId) async {
    final r = await _post('/api/Space/leave', {'id': bookingId});
    final msg = '${r['msg'] ?? r['message'] ?? ''}'.trim();
    return msg.isEmpty ? '已暂离' : msg;
  }

  /// Checks out of an active booking (签退).
  Future<String> checkoutBooking(String bookingId) async {
    final r = await _post('/api/Space/checkout', {'id': bookingId});
    final msg = '${r['msg'] ?? r['message'] ?? ''}'.trim();
    return msg.isEmpty ? '已签退' : msg;
  }

  /// Cancels a seat or seminar room booking.
  Future<String> cancelBooking(LibraryBooking booking) async {
    final path = booking.isRoom ? '/api/Seminar/roomCancel' : '/api/Space/cancel';
    final r = await _post(path, {'id': booking.id});
    final msg = '${r['msg'] ?? r['message'] ?? ''}'.trim();
    return msg.isEmpty ? '已取消预约' : msg;
  }

  /// Renews a seat booking (续座, AES-encrypted payload).
  Future<String> renewBooking(LibraryBooking booking) async {
    final r = await _post(
      '/api/seat/xuzuoconfirm',
      {'seat_id': booking.spaceId, 'segment': booking.xuzuoSegment},
      encrypted: true,
    );
    final msg = '${r['msg'] ?? r['message'] ?? ''}'.trim();
    return msg.isEmpty ? '续座成功' : msg;
  }

  Future<LibraryMember> member() async {
    final r = await _post('/api/Member/my', const {});
    final d = r['data'];
    if (d is! Map) {
      throw AppError(AppErrorKind.schemaOrRedirect, message: '图书馆账号信息缺失');
    }
    final qr = '${d['qrcode_image'] ?? ''}'.replaceAll(RegExp(r'\s'), '');
    return LibraryMember(
      name: '${d['name'] ?? ''}',
      roleName: '${d['roleName'] ?? ''}',
      qrImage: qr.startsWith('data:') ? qr : null,
    );
  }

  void reset() => _token = null;
}
