// Verifies the Dart DES login-password port is byte-identical to the real site JS.
//
// The fixture des_login_vectors.json was produced by running the site's actual
// static-snapshot/.../des.min.js + jquery.base64.min.js under Node (see the
// repo-root generation notes). If this test passes, encodeLoginPassword produces
// exactly the loginPwd the browser would.
import 'dart:convert';
import 'dart:io';

import 'package:nwafu_xk/core/crypto/des_login.dart';
import 'package:test/test.dart';

void main() {
  group('DES login crypto matches site JS vectors', () {
    final fixture = File('test/des_login_vectors.json');
    final vectors = jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;

    vectors.forEach((password, expected) {
      final exp = expected as Map<String, dynamic>;
      test('password ${password.isEmpty ? '(empty)' : '"$password"'}', () {
        expect(
          strEnc(password, 'this', 'password', 'is'),
          exp['strEncHex'],
          reason: 'strEnc hex mismatch',
        );
        expect(
          encodeLoginPassword(password),
          exp['loginPwd'],
          reason: 'loginPwd base64 mismatch',
        );
      });
    });
  });

  test('empty password encodes to empty string', () {
    expect(encodeLoginPassword(''), '');
  });
}
