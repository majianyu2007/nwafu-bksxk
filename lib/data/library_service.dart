/// 图书馆空间预约 (booking-lib.nwafu.edu.cn): free seats and seminar rooms,
/// the student's bookings and the library entrance QR code.
///
/// Sign-in rides on the unified identity: `GET /api/cas/cas` goes through
/// the AuthServer and lands on `/h5/index.html#/cas/?cas=<code>`; `POST
/// /api/cas/user {cas}` trades the code for a bearer token, which every call
/// then carries both as the `authorization` header and in the JSON body.
///
/// Read-only on purpose. Booking, signing in and cancelling post AES-encrypted
/// bodies built by the official page; the app opens that page for them
/// instead of reimplementing the encryption.
library;

import 'package:dio/dio.dart';

import '../core/errors.dart';
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
    required this.name,
    required this.campus,
    required this.floor,
    required this.typeName,
    this.total,
    this.free,
    this.capacity,
    this.fullyBooked = false,
    this.description = '',
  });

  factory LibraryArea.fromJson(Map<String, dynamic> j) {
    int? n(Object? v) => v == null ? null : int.tryParse('$v');
    final merge = '${j['nameMerge'] ?? ''}'.split('-');
    return LibraryArea(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      campus: '${j['premisesName'] ?? (merge.isNotEmpty ? merge.first : '')}',
      floor: '${j['storeyName'] ?? (merge.length > 1 ? merge[1] : '')}',
      typeName: '${j['type_name'] ?? ''}',
      total: n(j['total_num']),
      free: n(j['free_num']),
      capacity: n(j['maxPerson']),
      fullyBooked: '${j['Fully_Booked'] ?? '0'}' == '1',
      description: '${j['sub_title'] ?? ''}'.trim(),
    );
  }

  final String id;
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
  });

  factory LibraryBooking.fromJson(Map<String, dynamic> j) => LibraryBooking(
    id: '${j['id']}',
    place: '${j['nameMerge'] ?? ''}',
    seat: '${j['no'] ?? j['name'] ?? ''}',
    day: '${j['day'] ?? ''}',
    start: '${j['start'] ?? ''}',
    end: '${j['end'] ?? ''}',
    status: '${j['status'] ?? ''}',
    statusName: '${j['statusName'] ?? ''}',
    begin: DateTime.tryParse('${j['beginTime'] ?? ''}'.replaceFirst(' ', 'T')),
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

  /// Still to come or in use (not 已结束 / 已取消 / 违约).
  bool get active =>
      !const {'已结束', '已取消', '已违约', '违约', '已完成'}.contains(statusName);
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

  Dio get _dio => cas.dio;

  Future<String> _login({bool retried = false}) async {
    final res = await cas.follow('$kLibraryOrigin/api/cas/cas');
    if (res.realUri.host == Uri.parse(kAuthServer).host && !retried) {
      // The AuthServer wants a login: the unified session has expired.
      if (await (onLoginRequired?.call() ?? Future.value(false))) {
        return _login(retried: true);
      }
    }
    final fragment = res.realUri.fragment;
    final code = Uri.tryParse(
      fragment.startsWith('/') ? 'x:$fragment' : 'x:/$fragment',
    )?.queryParameters['cas'];
    if (code == null || code.isEmpty) {
      throw AppError(
        AppErrorKind.sessionExpired,
        message: '图书馆登录没有完成',
        hint: '统一身份认证可能已过期，请重新登录后再试。',
      );
    }
    final r = await _post('/api/cas/user', {'cas': code}, auth: false);
    final token = (r['member'] as Map?)?['token']?.toString();
    if (token == null || token.isEmpty) {
      throw AppError(AppErrorKind.unknown, message: '图书馆没有返回登录凭证');
    }
    return _token = token;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
    bool retried = false,
  }) async {
    final token = auth ? (_token ?? await _login()) : null;
    final res = await _dio.post<dynamic>(
      '$kLibraryOrigin$path',
      data: {...body, if (token != null) 'authorization': 'bearer$token'},
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        followRedirects: false,
        validateStatus: (_) => true,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'lang': 'zh',
          if (token != null) 'authorization': 'bearer$token',
        },
      ),
    );
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw AppError(AppErrorKind.schemaOrRedirect, message: '图书馆系统返回了无法识别的内容');
    }
    final code = '${data['code']}';
    if (code == '10001' && auth && !retried) {
      _token = null;
      return _post(path, body, retried: true);
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
              .map(LibraryBooking.fromJson)
              .toList()
        : const [];
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
