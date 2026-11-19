import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:nwafu_bksxk/core/crypto/library_crypto.dart';
import 'package:nwafu_bksxk/data/library_service.dart';

void main() {
  group('library_crypto', () {
    test('derives YYYYMMDD + reversed(YYYYMMDD) in Beijing time', () {
      // 2026-11-19 18:00 UTC == 2026-11-20 02:00 CST (Beijing)
      final key = libraryAesKey(DateTime.utc(2026, 11, 19, 18, 0));
      expect(utf8.decode(key), '2026112002116202');
      expect(key.length, 16);
    });

    test('round-trips seat booking payload via AES-128-CBC-PKCS7', () {
      final now = DateTime.utc(2026, 11, 19, 6, 0);
      final payload = {'seat_id': '12345', 'segment': '67890'};
      final cipher = encryptLibraryPayload(payload, now: now);
      final plain = decryptLibraryPayload(cipher, now: now);
      expect(jsonDecode(plain), payload);
    });
  });

  group('LibraryBooking actions', () {
    test('enables sign-in and cancel for pending seat booking', () {
      final b = LibraryBooking.fromJson({
        'id': '101',
        'nameMerge': '北校图书馆-二层自习区',
        'no': 'A012',
        'day': '2026-11-19',
        'start': '08:00',
        'end': '12:00',
        'status': '1',
        'statusName': '预约成功',
        'space_id': '55',
      });
      expect(b.active, isTrue);
      expect(b.canSignIn, isTrue);
      expect(b.canCancel, isTrue);
      expect(b.canLeave, isFalse);
      expect(b.canCheckout, isFalse);
    });

    test('enables leave, checkout, and renew for in-use seat booking', () {
      final b = LibraryBooking.fromJson({
        'id': '102',
        'nameMerge': '北校图书馆-二层自习区',
        'no': 'A012',
        'day': '2026-11-19',
        'start': '08:00',
        'end': '12:00',
        'status': '2',
        'statusName': '使用中',
        'space_id': '55',
        'xuzuosegment': '999',
      });
      expect(b.active, isTrue);
      expect(b.canLeave, isTrue);
      expect(b.canCheckout, isTrue);
      expect(b.canRenew, isTrue);
      expect(b.canCancel, isFalse);
    });
  });

  group('LibrarySeatMap, coordinates & SeminarDay', () {
    test('resolves relative floorplan image URLs', () {
      final map = LibrarySeatMap.fromJson({'free': '/uploads/floor2.png'});
      expect(map.hasImage, isTrue);
      expect(map.freeUrl, 'https://booking-lib.nwafu.edu.cn/uploads/floor2.png');
    });

    test('parses seat percentage coordinates and visual status', () {
      final seat = LibrarySeat.fromJson({
        'id': '99',
        'no': 'A012',
        'status': '1',
        'point_x': '12.5',
        'point_y': '34.0',
        'width': '3.2',
        'height': '4.1',
        'in_label': 1,
      });
      expect(seat.hasCoords, isTrue);
      expect(seat.isFree, isTrue);
      expect(seat.visualStatus, LibrarySeatStatus.free);
      expect(seat.pointX, 12.5);
    });

    test('parses seminar day constraints and booked ranges', () {
      final day = LibrarySeminarDay.fromJson('2026-11-20', {
        'minPerson': 3,
        'maxPerson': 8,
        'start_time': '08:00',
        'end_time': '22:00',
        'list': [
          {'start_time': '10:00', 'end_time': '12:00'},
        ],
      });
      expect(day.minPerson, 3);
      expect(day.maxPerson, 8);
      expect(day.bookedRanges, [('10:00', '12:00')]);
    });

    test('LibraryArea.fromJson resolves firstimg relative and absolute URLs', () {
      final rel = LibraryArea.fromJson({
        'id': 401,
        'name': '201研讨室',
        'firstimg': '/Uploads/space/201.jpg',
      });
      expect(
        rel.imageUrl,
        'https://booking-lib.nwafu.edu.cn/Uploads/space/201.jpg',
      );

      final abs = LibraryArea.fromJson({
        'id': 402,
        'name': '202研讨室',
        'thumb_img': 'https://cdn.example.com/202.png',
      });
      expect(abs.imageUrl, 'https://cdn.example.com/202.png');
    });

    test('parses live NWAFU /api/Seminar/seminar timestamps & camelCase keys', () {
      // Exact schema captured from live NWAFU booking-lib read-only probe.
      final day = LibrarySeminarDay.fromJson('2026-11-19', {
        'startTime': 1795046400, // 2026-11-19 08:00 CST
        'endTime': 1795096800, // 2026-11-19 22:00 CST
        'minTime': '30',
        'maxTime': '240',
        'minPerson': '1',
        'maxPerson': '2',
        'list': [
          {
            'id': '71085',
            'beginTime': 1795068900,
            'endTime': 1795082400,
            'beginTimestamp': '2026-11-19 14:15:00',
            'endTimestamp': '2026-11-19 18:00:00',
          },
          {
            'id': '71092',
            'beginTime': 1795049100,
            'endTime': 1795062600,
            'beginTimestamp': '2026-11-19 08:45:00',
            'endTimestamp': '2026-11-19 12:30:00',
          },
        ],
      });
      expect(day.openStart, '08:00');
      expect(day.openEnd, '22:00');
      expect(day.minDurationMinutes, 30);
      expect(day.maxDurationMinutes, 240);
      expect(day.bookedRanges, [
        ('08:45', '12:30'),
        ('14:15', '18:00'),
      ]);
    });

    test('LibraryArea skips 404 defaults, reads img List, encodes Chinese URLs', () {
      final placeholder = LibraryArea.fromJson({
        'id': 71,
        'name': '培训教室',
        'firstimg':
            'https://booking-lib.nwafu.edu.cn/upload/premises/defaultfirstimg.jpg',
        'img': [
          'https://booking-lib.nwafu.edu.cn/upload/premises/defaultcarouseimg.jpg',
        ],
      });
      expect(placeholder.imageUrl, isEmpty);

      final cn = LibraryArea.fromJson({
        'id': 49,
        'name': '阅创空间2202',
        'firstimg':
            'https://booking-lib.nwafu.edu.cn/upload/premises/defaultfirstimg.jpg',
        'img': [
          'https://booking-lib.nwafu.edu.cn/home/images/carousel/area/49/南校区2202.jpg',
        ],
      });
      expect(
        cn.imageUrl,
        'https://booking-lib.nwafu.edu.cn/home/images/carousel/area/49/%E5%8D%97%E6%A0%A1%E5%8C%BA2202.jpg',
      );
    });

    test('LibraryBooking handles live /api/Member/seminar lowercase statusname', () {
      final past = LibraryBooking.fromJson({
        'id': '66083',
        'nameMerge': '北校区-3F-研讨间327',
        'title': '开会',
        'day': '10-17',
        'start': '2026-10-17',
        'end': '2026-10-17',
        'status': '8',
        'statusname': '已关闭',
        'beginTime': '2026-10-17 18:00:00',
        'endTime': '2026-10-17 20:00:00',
      }, isRoom: true);
      expect(past.statusName, '已关闭');
      expect(past.active, isFalse);
      expect(past.start, '18:00');
      expect(past.end, '20:00');
      expect(past.seat, '开会');
    });

    test('LibrarySeat parses alumni donor info when present', () {
      final seat = LibrarySeat.fromJson({
        'id': '12',
        'no': '3101',
        'status': '1',
        'donate': {
          'donate_title': '捐献人',
          'donate_name': '张校友',
          'donate_dept': '信息工程学院',
          'donate_major': '软件工程',
        },
      });
      expect(seat.donorLabel, '捐献人：张校友（信息工程学院 软件工程）');
    });
  });
}
