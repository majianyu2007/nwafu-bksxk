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

import 'package:pointycastle/export.dart';

const String _kLibraryIv = 'ZZWBKJ_ZHIHUAWEI';

/// Derives the 16-byte daily AES key from [date] (interpreted in Beijing time
/// UTC+8 when [date] is not already UTC-date-only).
Uint8List libraryAesKey(DateTime date) {
  final bj = date.toUtc().add(const Duration(hours: 8));
  final y = bj.year.toString().padLeft(4, '0');
  final m = bj.month.toString().padLeft(2, '0');
  final d = bj.day.toString().padLeft(2, '0');
  final day = '$y$m$d';
  final rev = String.fromCharCodes(day.codeUnits.reversed);
  return Uint8List.fromList(utf8.encode('$day$rev'));
}

/// Encrypts [payload] into the base64 `aesjson` string expected by
/// `booking-lib.nwafu.edu.cn`.
String encryptLibraryPayload(Map<String, dynamic> payload, {DateTime? now}) {
  final key = libraryAesKey(now ?? DateTime.now());
  final iv = Uint8List.fromList(utf8.encode(_kLibraryIv));
  final plain = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  )..init(
      true,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );
  return base64.encode(cipher.process(plain));
}

/// Decrypts an `aesjson` string back to its UTF-8 JSON text (used in tests).
String decryptLibraryPayload(String aesjson, {DateTime? now}) {
  final key = libraryAesKey(now ?? DateTime.now());
  final iv = Uint8List.fromList(utf8.encode(_kLibraryIv));
  final bytes = base64.decode(aesjson);
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  )..init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );
  return utf8.decode(cipher.process(bytes));
}
