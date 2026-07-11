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

  List<List<int>>? firstKeyBt;
  List<List<int>>? secondKeyBt;
  List<List<int>>? thirdKeyBt;
  var firstLength = 0;
  var secondLength = 0;
  var thirdLength = 0;

  if (firstKey.isNotEmpty) {
    firstKeyBt = _getKeyBytes(firstKey);
    firstLength = firstKeyBt.length;
  }
  if (secondKey.isNotEmpty) {
    secondKeyBt = _getKeyBytes(secondKey);
    secondLength = secondKeyBt.length;
  }
  if (thirdKey.isNotEmpty) {
    thirdKeyBt = _getKeyBytes(thirdKey);
    thirdLength = thirdKeyBt.length;
  }

  final buffer = StringBuffer();

  List<int> encryptBlock(List<int> block) {
    var enc = block;
    if (firstKey.isNotEmpty && secondKey.isNotEmpty && thirdKey.isNotEmpty) {
      for (var b = 0; b < firstLength; b++) {
        enc = _enc(enc, firstKeyBt![b]);
      }
      for (var h = 0; h < secondLength; h++) {
        enc = _enc(enc, secondKeyBt![h]);
      }
      for (var x = 0; x < thirdLength; x++) {
        enc = _enc(enc, thirdKeyBt![x]);
      }
    } else if (firstKey.isNotEmpty && secondKey.isNotEmpty) {
      for (var b = 0; b < firstLength; b++) {
        enc = _enc(enc, firstKeyBt![b]);
      }
      for (var h = 0; h < secondLength; h++) {
        enc = _enc(enc, secondKeyBt![h]);
      }
    } else if (firstKey.isNotEmpty) {
      for (var b = 0; b < firstLength; b++) {
        enc = _enc(enc, firstKeyBt![b]);
      }
    }
    return enc;
  }

  if (length < 4) {
    final block = _strToBt(data);
    buffer.write(_bt64ToHex(encryptBlock(block)));
    return buffer.toString();
  }

  final iterator = length ~/ 4;
  final remainder = length % 4;
  for (var i = 0; i < iterator; i++) {
    final group = data.substring(i * 4, i * 4 + 4);
    buffer.write(_bt64ToHex(encryptBlock(_strToBt(group))));
  }
  if (remainder > 0) {
    final group = data.substring(iterator * 4, length);
    buffer.write(_bt64ToHex(encryptBlock(_strToBt(group))));
  }
  return buffer.toString();
}

/// Splits a key string into 4-char sub-blocks, each turned into a 64-bit array.
List<List<int>> _getKeyBytes(String key) {
  final result = <List<int>>[];
  final length = key.length;
  final iterator = length ~/ 4;
  final remainder = length % 4;
  var i = 0;
  for (i = 0; i < iterator; i++) {
    result.add(_strToBt(key.substring(i * 4, i * 4 + 4)));
  }
  if (remainder > 0) {
    result.add(_strToBt(key.substring(i * 4, length)));
  }
  return result;
}

/// Turns up to 4 chars into a 64-bit array (16 bits per char, big-endian),
/// zero-padding when fewer than 4 chars are present.
List<int> _strToBt(String str) {
  final length = str.length;
  final bt = List<int>.filled(64, 0);
  if (length < 4) {
    for (var i = 0; i < length; i++) {
      final code = str.codeUnitAt(i);
      for (var j = 0; j < 16; j++) {
        var pow = 1;
        for (var m = 15; m > j; m--) {
          pow *= 2;
        }
        bt[16 * i + j] = (code ~/ pow) % 2;
      }
    }
    // Chars beyond the string length pad with zero bits. bt is already
    // zero-filled, so the original JS's explicit zero-write loop is a no-op here.
  } else {
    for (var i = 0; i < 4; i++) {
      final code = str.codeUnitAt(i);
      for (var j = 0; j < 16; j++) {
        var pow = 1;
        for (var m = 15; m > j; m--) {
          pow *= 2;
        }
        bt[16 * i + j] = (code ~/ pow) % 2;
      }
    }
  }
  return bt;
}

String _bt4ToHex(String binary) {
  switch (binary) {
    case '0000': return '0';
    case '0001': return '1';
    case '0010': return '2';
    case '0011': return '3';
    case '0100': return '4';
    case '0101': return '5';
    case '0110': return '6';
    case '0111': return '7';
    case '1000': return '8';
    case '1001': return '9';
    case '1010': return 'A';
    case '1011': return 'B';
    case '1100': return 'C';
    case '1101': return 'D';
    case '1110': return 'E';
    case '1111': return 'F';
    default: return '';
  }
}

String _bt64ToHex(List<int> byteData) {
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    final group = StringBuffer();
    for (var j = 0; j < 4; j++) {
      group.write(byteData[4 * i + j]);
    }
    buffer.write(_bt4ToHex(group.toString()));
  }
  return buffer.toString();
}

List<int> _enc(List<int> dataBt, List<int> keyBt) {
  final keys = _generateKeys(keyBt);
  final ip = _initPermute(dataBt);
  final liArr = List<int>.filled(32, 0);
  final riArr = List<int>.filled(32, 0);
  for (var m = 0; m < 32; m++) {
    liArr[m] = ip[m];
    riArr[m] = ip[32 + m];
  }

  final li = liArr;
  var ri = riArr;
  for (var round = 0; round < 16; round++) {
    final mid = List<int>.filled(32, 0);
    for (var n = 0; n < 32; n++) {
      mid[n] = li[n];
      li[n] = ri[n];
    }
    final key = List<int>.filled(48, 0);
    for (var n = 0; n < 48; n++) {
      key[n] = keys[round][n];
    }
    final expanded = _xor(_pPermute(_sBoxPermute(_xor(_expandPermute(ri), key))), mid);
    ri = List<int>.from(expanded);
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
    // NOTE: this mirrors the site's exact (mathematically odd) index formula.
    final line = 2 * expandPermuted[6 * m + 0] + expandPermuted[6 * m + 5];
    final row = 2 * expandPermuted[6 * m + 1] * 2 * 2 +
        2 * expandPermuted[6 * m + 2] * 2 +
        2 * expandPermuted[6 * m + 3] +
        expandPermuted[6 * m + 4];
    final value = _getBoxBinary(_sBoxes[m][line][row]);
    sBoxPermuted[4 * m + 0] = int.parse(value.substring(0, 1));
    sBoxPermuted[4 * m + 1] = int.parse(value.substring(1, 2));
    sBoxPermuted[4 * m + 2] = int.parse(value.substring(2, 3));
    sBoxPermuted[4 * m + 3] = int.parse(value.substring(3, 4));
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

String _getBoxBinary(int i) {
  const table = [
    '0000', '0001', '0010', '0011', '0100', '0101', '0110', '0111',
    '1000', '1001', '1010', '1011', '1100', '1101', '1110', '1111',
  ];
  return table[i];
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
