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
  });
}
