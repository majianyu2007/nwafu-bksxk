import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/core/crypto/passkey.dart';
import 'package:nwafu_bksxk/core/crypto/webauthn_register.dart';
import 'package:pointycastle/export.dart';

Map<String, dynamic> options() => {
  'rp': {'id': 'authserver.nwafu.edu.cn', 'name': 'authserver'},
  'user': {'id': 'MjAyNTAxMzY2NQ', 'name': '2025013665'},
  'challenge': 'q1w2e3r4t5y6u7i8o9p0',
  'pubKeyCredParams': [
    {'type': 'public-key', 'alg': -7},
    {'type': 'public-key', 'alg': -257},
  ],
  'excludeCredentials': <Object>[],
};

void main() {
  test('CBOR round-trips the shapes WebAuthn uses', () {
    final v = {
      'fmt': 'none',
      'attStmt': <String, Object>{},
      1: 2,
      -2: Uint8List.fromList(List.generate(32, (i) => i)),
      'n': -300,
      'big': 70000,
    };
    final decoded = cborDecode(cborEncode(v)) as Map;
    expect(decoded['fmt'], 'none');
    expect(decoded[1], 2);
    expect(decoded['n'], -300);
    expect(decoded['big'], 70000);
    expect(decoded[-2], v[-2]);
  });

  test('registration carries a parseable COSE key matching the stored key',
      () {
    final reg = buildRegistrationCredential(
      options: options(),
      origin: 'https://authserver.nwafu.edu.cn',
      random: Random(1),
    );
    final resp = reg.response['response'] as Map;
    final client = jsonDecode(
      utf8.decode(b64Decode(resp['clientDataJSON'] as String)),
    ) as Map;
    expect(client['type'], 'webauthn.create');
    expect(client['challenge'], 'q1w2e3r4t5y6u7i8o9p0');
    expect(client['origin'], 'https://authserver.nwafu.edu.cn');

    final att = cborDecode(b64Decode(resp['attestationObject'] as String))
        as Map;
    expect(att['fmt'], 'none');
    final auth = att['authData'] as Uint8List;
    expect(
      auth.sublist(0, 32),
      hash.sha256.convert(utf8.encode('authserver.nwafu.edu.cn')).bytes,
    );
    expect(auth[32] & 0x45, 0x45, reason: 'UP, UV and AT flags');
    final idLen = auth[53] << 8 | auth[54];
    final credId = auth.sublist(55, 55 + idLen);
    expect(b64UrlEncode(credId), reg.response['id']);
    expect(reg.credential.rawId, credId);

    final cose = cborDecode(Uint8List.sublistView(auth, 55 + idLen)) as Map;
    expect(cose[3], -7);
    final q = registrationPublicKey(reg.credential);
    BigInt n(Uint8List b) =>
        b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));
    expect(n(cose[-2] as Uint8List), q.x!.toBigInteger());
    expect(n(cose[-3] as Uint8List), q.y!.toBigInteger());
    expect(reg.credential.userHandle, 'MjAyNTAxMzY2NQ');
  });

  test('a bound credential then produces assertions the COSE key verifies',
      () {
    final reg = buildRegistrationCredential(
      options: options(),
      origin: 'https://authserver.nwafu.edu.cn',
      random: Random(2),
    );
    final c = PasskeyCredential(
      credentialId: reg.credential.credentialId,
      keyValue: reg.credential.keyValue,
      rpId: reg.credential.rpId,
      deviceBindingId: 'device-1',
    );
    final a = buildPasskeyAssertion(
      credential: c,
      challenge: 'abc',
      origin: 'https://authserver.nwafu.edu.cn',
      random: Random(3),
    );
    final r = a['response'] as Map;
    final signed = Uint8List.fromList([
      ...b64Decode(r['authenticatorData'] as String),
      ...hash.sha256.convert(b64Decode(r['clientDataJSON'] as String)).bytes,
    ]);
    expect(
      verifyP256(
        registrationPublicKey(c),
        signed,
        b64Decode(r['signature'] as String),
      ),
      isTrue,
    );
  });

  test('packed self-attestation is signed by the credential key', () {
    final reg = buildRegistrationCredential(
      options: options(),
      origin: 'https://authserver.nwafu.edu.cn',
      format: AttestationFormat.packedSelf,
      random: Random(4),
    );
    final resp = reg.response['response'] as Map;
    final att = cborDecode(b64Decode(resp['attestationObject'] as String))
        as Map;
    expect(att['fmt'], 'packed');
    final stmt = att['attStmt'] as Map;
    expect(stmt['alg'], -7);
    final signed = Uint8List.fromList([
      ...att['authData'] as Uint8List,
      ...hash.sha256.convert(b64Decode(resp['clientDataJSON'] as String)).bytes,
    ]);
    final ECPoint q = registrationPublicKey(reg.credential);
    expect(verifyP256(q, signed, stmt['sig'] as Uint8List), isTrue);
  });

  test('refuses servers that do not accept ES256', () {
    expect(
      () => buildRegistrationCredential(
        options: {
          ...options(),
          'pubKeyCredParams': [
            {'type': 'public-key', 'alg': -257},
          ],
        },
        origin: 'https://authserver.nwafu.edu.cn',
      ),
      throwsA(isA<PasskeyException>()),
    );
  });
}
