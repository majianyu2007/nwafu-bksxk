/// AES-128-CBC + PKCS#7 payload cipher for `booking-lib.nwafu.edu.cn`
/// (`encryptRequest` endpoints such as `/api/Seat/confirm` and
/// `/api/seat/xuzuoconfirm`).
///
/// Matches the H5 bundle (`encrypt("encrypt", data)`):
/// - `d = YYYYMMDD` (Beijing time)
/// - `key = utf8(d + reverse(d))` (16 bytes)
/// - `iv  = utf8("ZZWBKJ_ZHIHUAWEI")` (16 bytes)
/// - `aesjson = base64(AES-128-CBC-PKCS7(utf8(jsonEncode(data)), key, iv))`
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pointycastle/export.dart';

const String _kLibraryIv = 'ZZWBKJ_ZHIHUAWEI';
final Uint8List _kLibraryIvBytes = Uint8List.fromList(_kLibraryIv.codeUnits);

/// Derives the 16-byte daily AES key from [date] (interpreted in Beijing time
/// UTC+8 when [date] is not already UTC-date-only).
Uint8List libraryAesKey(DateTime date) {
  final bj = date.toUtc().add(const Duration(hours: 8));
  final y = bj.year.toString().padLeft(4, '0');
  final m = bj.month.toString().padLeft(2, '0');
  final d = bj.day.toString().padLeft(2, '0');
  final day = '$y$m$d';
  final rev = String.fromCharCodes(day.codeUnits.reversed);
  return utf8.encode('$day$rev');
}

PaddedBlockCipherImpl _libraryCipher(Uint8List key, {required bool encrypt}) =>
    PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        encrypt,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), _kLibraryIvBytes),
          null,
        ),
      );

/// Encrypts [payload] into the base64 `aesjson` string expected by
/// `booking-lib.nwafu.edu.cn`.
String encryptLibraryPayload(Map<String, dynamic> payload, {DateTime? now}) {
  final key = libraryAesKey(now ?? DateTime.now());
  final plain = utf8.encode(jsonEncode(payload));
  return base64.encode(_libraryCipher(key, encrypt: true).process(plain));
}

/// Decrypts an `aesjson` string back to its UTF-8 JSON text (used in tests).
@visibleForTesting
String decryptLibraryPayload(String aesjson, {DateTime? now}) {
  final key = libraryAesKey(now ?? DateTime.now());
  final bytes = base64.decode(aesjson);
  return utf8.decode(_libraryCipher(key, encrypt: false).process(bytes));
}
