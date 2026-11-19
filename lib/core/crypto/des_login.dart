// A faithful Dart port of the site's `des.min.js` `strEnc` login-password cipher.
//
// The NWAFU login form computes:
//     loginPwd = base64( strEnc(password, "this", "password", "is") )
// where `strEnc` is a home-grown triple-pass DES-like block cipher that emits an
// uppercase hex string, and `base64` (jquery.base64) then encodes that ASCII hex.
//
// This is NOT standard DES: the block is built from UTF-16 code units two bytes
// at a time (4 chars per 64-bit block), sub-blocks shorter than 4 chars are zero
// padded, and each 4-char group is encrypted once per key character. To stay
// bug-for-bug compatible with the server we transliterate the original routine
// rather than substitute a library. Verified against vectors captured by running
// the real site JS under Node (see test/des_login_test.dart).
library;

import 'dart:convert';

/// The three DES keys the login page hard-codes via `getDesKeys()`.
const List<String> kLoginDesKeys = ['this', 'password', 'is'];

/// Encrypts [password] the way the login page does and returns the base64 value
/// to send as `loginPwd`.
String encodeLoginPassword(String password) {
  final hex = strEnc(password, kLoginDesKeys[0], kLoginDesKeys[1], kLoginDesKeys[2]);
  // jquery.base64.encode over an ASCII hex string == standard base64 of its bytes.
  return base64.encode(ascii.encode(hex));
}

/// Port of `strEnc(str, firstKey, secondKey, thirdKey)`.
String strEnc(String data, String firstKey, String secondKey, String thirdKey) {
  final length = data.length;
  if (length == 0) return '';

  // Mirror des.min.js key-presence prefix semantics: secondKey only applies
  // when firstKey is non-empty, and thirdKey only when both preceding keys are.
  final schedules = <List<List<int>>>[];
  if (firstKey.isNotEmpty) {
    for (final k in _getKeyBytes(firstKey)) {
      schedules.add(_generateKeys(k));
    }
    if (secondKey.isNotEmpty) {
      for (final k in _getKeyBytes(secondKey)) {
        schedules.add(_generateKeys(k));
      }
      if (thirdKey.isNotEmpty) {
        for (final k in _getKeyBytes(thirdKey)) {
          schedules.add(_generateKeys(k));
        }
      }
    }
  }

  List<int> encryptBlock(List<int> block) {
    var enc = block;
    for (final schedule in schedules) {
      enc = _enc(enc, schedule);
    }
    return enc;
  }

  final buffer = StringBuffer();
  for (var start = 0; start < length; start += 4) {
    final end = start + 4 <= length ? start + 4 : length;
    buffer.write(_bt64ToHex(encryptBlock(_strToBt(data.substring(start, end)))));
  }
  return buffer.toString();
}

/// Splits a key string into 4-char sub-blocks, each turned into a 64-bit array.
List<List<int>> _getKeyBytes(String key) => [
      for (var start = 0; start < key.length; start += 4)
        _strToBt(key.substring(start, start + 4 <= key.length ? start + 4 : key.length)),
    ];

/// Turns up to 4 chars into a 64-bit array (16 bits per char, big-endian),
/// zero-padding when fewer than 4 chars are present.
List<int> _strToBt(String str) {
  final count = str.length < 4 ? str.length : 4;
  final bt = List<int>.filled(64, 0);
  for (var i = 0; i < count; i++) {
    final code = str.codeUnitAt(i);
    final base = 16 * i;
    for (var j = 0; j < 16; j++) {
      bt[base + j] = (code >> (15 - j)) & 1;
    }
  }
  return bt;
}

const _hexDigits = '0123456789ABCDEF';

String _bt64ToHex(List<int> byteData) {
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    final base = 4 * i;
    final nibble = (byteData[base] << 3) |
        (byteData[base + 1] << 2) |
        (byteData[base + 2] << 1) |
        byteData[base + 3];
    buffer.write(_hexDigits[nibble]);
  }
  return buffer.toString();
}

List<int> _enc(List<int> dataBt, List<List<int>> keys) {
  final ip = _initPermute(dataBt);
  var li = ip.sublist(0, 32);
  var ri = ip.sublist(32, 64);

  for (var round = 0; round < 16; round++) {
    final prevLi = li;
    li = ri;
    ri = _xor(_pPermute(_sBoxPermute(_xor(_expandPermute(ri), keys[round]))), prevLi);
  }

  final result = List<int>.filled(64, 0);
  for (var n = 0; n < 32; n++) {
    result[n] = ri[n];
    result[32 + n] = li[n];
  }
  return _finallyPermute(result);
}

List<int> _initPermute(List<int> originalData) {
  final ip = List<int>.filled(64, 0);
  var m = 1;
  var n = 0;
  for (var i = 0; i < 4; i++, m += 2, n += 2) {
    var k = 0;
    for (var j = 7; j >= 0; j--, k++) {
      ip[8 * i + k] = originalData[8 * j + m];
      ip[8 * i + k + 32] = originalData[8 * j + n];
    }
  }
  return ip;
}

List<int> _expandPermute(List<int> rightData) {
  final epd = List<int>.filled(48, 0);
  for (var i = 0; i < 8; i++) {
    epd[6 * i + 0] = i == 0 ? rightData[31] : rightData[4 * i - 1];
    epd[6 * i + 1] = rightData[4 * i + 0];
    epd[6 * i + 2] = rightData[4 * i + 1];
    epd[6 * i + 3] = rightData[4 * i + 2];
    epd[6 * i + 4] = rightData[4 * i + 3];
    epd[6 * i + 5] = i == 7 ? rightData[0] : rightData[4 * i + 4];
  }
  return epd;
}

List<int> _xor(List<int> a, List<int> b) {
  final result = List<int>.filled(a.length, 0);
  for (var i = 0; i < a.length; i++) {
    result[i] = a[i] ^ b[i];
  }
  return result;
}

const List<List<List<int>>> _sBoxes = [
  [
    [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
    [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
    [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
    [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
  ],
  [
    [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
    [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
    [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
    [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
  ],
  [
    [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
    [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
    [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
    [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
  ],
  [
    [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
    [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
    [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
    [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
  ],
  [
    [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
    [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
    [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
    [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
  ],
  [
    [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
    [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
    [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
    [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
  ],
  [
    [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
    [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
    [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
    [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
  ],
  [
    [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
    [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
    [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
    [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
  ],
];

List<int> _sBoxPermute(List<int> expandPermuted) {
  final sBoxPermuted = List<int>.filled(32, 0);
  for (var m = 0; m < 8; m++) {
    final base = 6 * m;
    final line = (expandPermuted[base] << 1) | expandPermuted[base + 5];
    final row = (expandPermuted[base + 1] << 3) |
        (expandPermuted[base + 2] << 2) |
        (expandPermuted[base + 3] << 1) |
        expandPermuted[base + 4];
    final v = _sBoxes[m][line][row];
    final out = 4 * m;
    sBoxPermuted[out] = (v >> 3) & 1;
    sBoxPermuted[out + 1] = (v >> 2) & 1;
    sBoxPermuted[out + 2] = (v >> 1) & 1;
    sBoxPermuted[out + 3] = v & 1;
  }
  return sBoxPermuted;
}

List<int> _pPermute(List<int> s) {
  const order = [
    15, 6, 19, 20, 28, 11, 27, 16, 0, 14, 22, 25, 4, 17, 30, 9,
    1, 7, 23, 13, 31, 26, 2, 8, 18, 12, 29, 5, 21, 10, 3, 24,
  ];
  final result = List<int>.filled(32, 0);
  for (var i = 0; i < 32; i++) {
    result[i] = s[order[i]];
  }
  return result;
}

List<int> _finallyPermute(List<int> endData) {
  const order = [
    39, 7, 47, 15, 55, 23, 63, 31, 38, 6, 46, 14, 54, 22, 62, 30,
    37, 5, 45, 13, 53, 21, 61, 29, 36, 4, 44, 12, 52, 20, 60, 28,
    35, 3, 43, 11, 51, 19, 59, 27, 34, 2, 42, 10, 50, 18, 58, 26,
    33, 1, 41, 9, 49, 17, 57, 25, 32, 0, 40, 8, 48, 16, 56, 24,
  ];
  final result = List<int>.filled(64, 0);
  for (var i = 0; i < 64; i++) {
    result[i] = endData[order[i]];
  }
  return result;
}

List<List<int>> _generateKeys(List<int> keyByte) {
  final key = List<int>.filled(56, 0);
  final keys = List<List<int>>.generate(16, (_) => List<int>.filled(48, 0));
  const loop = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];

  for (var i = 0; i < 7; i++) {
    for (var j = 0, k = 7; j < 8; j++, k--) {
      key[8 * i + j] = keyByte[8 * k + i];
    }
  }
  for (var i = 0; i < 16; i++) {
    for (var j = 0; j < loop[i]; j++) {
      final tempLeft = key[0];
      final tempRight = key[28];
      for (var k = 0; k < 27; k++) {
        key[k] = key[k + 1];
        key[28 + k] = key[29 + k];
      }
      key[27] = tempLeft;
      key[55] = tempRight;
    }

    const sel = [
      13, 16, 10, 23, 0, 4, 2, 27, 14, 5, 20, 9, 22, 18, 11, 3,
      25, 7, 15, 6, 26, 19, 12, 1, 40, 51, 30, 36, 46, 54, 29, 39,
      50, 44, 32, 47, 43, 48, 38, 55, 33, 52, 45, 41, 49, 35, 28, 31,
    ];
    for (var m = 0; m < 48; m++) {
      keys[i][m] = key[sel[m]];
    }
  }
  return keys;
}
