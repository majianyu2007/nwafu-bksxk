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
}
