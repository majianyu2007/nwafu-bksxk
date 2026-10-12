/// WebAuthn assertions for the Wisedu AuthServer's 生物识别 (passkey) login,
/// produced in software from an exported P-256 key. A port of
/// `wisedu_cas/fido2.py`, which reproduces what `navigator.credentials.get()`
/// returns in the browser.
///
/// The site ties a passkey to a browser through three localStorage entries on
/// the login page, not a cookie: `anonbiometricsu` (base64 of the login name),
/// `anonbiometricsd` (the device-binding id the server issued at
/// registration) and `anonbiometricso` (a "biometrics on" flag). The server
/// only checks that the user + device id have a registered credential, so the
/// credential id, private key and device id together are enough to sign in
/// from any client, which is what [PasskeyCredential] holds.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

/// An exported passkey for the school's AuthServer.
class PasskeyCredential {
  const PasskeyCredential({
    required this.credentialId,
    required this.keyValue,
    required this.rpId,
    required this.deviceBindingId,
    this.userHandle = '',
  });

  /// The credential id: UUID-style hex (Bitwarden) or base64url.
  final String credentialId;

  /// The private key: base64/base64url PKCS#8 or SEC1 DER (P-256).
  final String keyValue;

  /// Relying party id, the AuthServer host.
  final String rpId;

  /// `anonbiometricsd` from the browser the passkey was registered in.
  final String deviceBindingId;
  final String userHandle;

  bool get isComplete =>
      credentialId.isNotEmpty &&
      keyValue.isNotEmpty &&
      rpId.isNotEmpty &&
      deviceBindingId.isNotEmpty;

  /// Accepts the JSON written by `extract_fido2.py --save` (a raw Bitwarden
  /// `fido2Credentials` entry plus `deviceBindingId`).
  factory PasskeyCredential.fromJson(Map<String, dynamic> j) =>
      PasskeyCredential(
        credentialId: (j['credentialId'] ?? '').toString().trim(),
        keyValue: (j['keyValue'] ?? '').toString().trim(),
        rpId: (j['rpId'] ?? j['rpID'] ?? '').toString().trim(),
        deviceBindingId:
            (j['deviceBindingId'] ?? j['anonbiometricsd'] ?? '').toString().trim(),
        userHandle: (j['userHandle'] ?? '').toString().trim(),
      );

  Map<String, dynamic> toJson() => {
        'credentialId': credentialId,
        'keyValue': keyValue,
        'rpId': rpId,
        'deviceBindingId': deviceBindingId,
        if (userHandle.isNotEmpty) 'userHandle': userHandle,
      };

  /// The raw credential id bytes.
  Uint8List get rawId {
    final hex = credentialId.replaceAll('-', '');
    if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex) && hex.length.isEven) {
      return Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16)
      ]);
    }
    return b64Decode(credentialId);
  }
}

class PasskeyException implements Exception {
  PasskeyException(this.message);
  final String message;
  @override
  String toString() => message;
}

String b64UrlEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodes standard or URL-safe base64, padded or not.
Uint8List b64Decode(String s) {
  var t = s.trim().replaceAll('-', '+').replaceAll('_', '/');
  t = t.padRight((t.length + 3) ~/ 4 * 4, '=');
  return base64.decode(t);
}

final _p256 = ECCurve_prime256v1();

/// Builds the assertion object the login form posts as `credential`.
/// [origin] is the AuthServer origin (`https://<rpId>`).
Map<String, dynamic> buildPasskeyAssertion({
  required PasskeyCredential credential,
  required String challenge,
  required String origin,
  Random? random,
}) {
  final d = _privateScalar(b64Decode(credential.keyValue));
  final clientData = utf8.encode(jsonEncode({
    'type': 'webauthn.get',
    'challenge': challenge,
    'origin': origin,
    'crossOrigin': false,
  }));
  // rpIdHash | flags (UP|UV|BE|BS, as a synced browser passkey) | signCount 0.
  final authData = Uint8List.fromList([
    ...hash.sha256.convert(utf8.encode(credential.rpId)).bytes,
    0x1D,
    0, 0, 0, 0,
  ]);
  final signed = Uint8List.fromList(
      [...authData, ...hash.sha256.convert(clientData).bytes]);
  final signature = signP256(d, signed, random: random);
  return {
    'id': b64UrlEncode(credential.rawId),
    'type': 'public-key',
    'response': {
      'authenticatorData': b64UrlEncode(authData),
      'clientDataJSON': b64UrlEncode(clientData),
      'signature': b64UrlEncode(signature),
      if (credential.userHandle.isNotEmpty) 'userHandle': credential.userHandle,
    },
    'clientExtensionResults': <String, dynamic>{},
  };
}

/// ECDSA-SHA256 over [message] with the P-256 scalar [d]; DER-encoded (r, s).
Uint8List signP256(BigInt d, Uint8List message, {Random? random}) {
  final r = random ?? Random.secure();
  final seed = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
  final signer = ECDSASigner(SHA256Digest())
    ..init(
      true,
      ParametersWithRandom(PrivateKeyParameter(ECPrivateKey(d, _p256)),
          FortunaRandom()..seed(KeyParameter(seed))),
    );
  final sig = (signer.generateSignature(message) as ECSignature).normalize(_p256);
  return _derSequence([_derInteger(sig.r), _derInteger(sig.s)]);
}

/// Verifies a DER signature; tests use it to check [signP256].
bool verifyP256(ECPoint q, Uint8List message, Uint8List der) {
  final seq = _DerReader(der).read(0x30);
  final reader = _DerReader(seq);
  final rr = _toBigInt(reader.read(0x02));
  final ss = _toBigInt(reader.read(0x02));
  final verifier = ECDSASigner(SHA256Digest())
    ..init(false, PublicKeyParameter(ECPublicKey(q, _p256)));
  return verifier.verifySignature(message, ECSignature(rr, ss));
}

/// The private scalar of a PKCS#8 / SEC1 key.
BigInt privateScalarOf(String keyValue) => _privateScalar(b64Decode(keyValue));

/// The public point for a key, for tests and diagnostics.
ECPoint publicPointOf(String keyValue) =>
    (_p256.G * _privateScalar(b64Decode(keyValue)))!;

/// A fresh P-256 key as base64url PKCS#8, the format Bitwarden exports.
String generatePasskeyKey({Random? random}) {
  final r = random ?? Random.secure();
  BigInt d;
  do {
    d = _toBigInt(Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))));
  } while (d == BigInt.zero || d >= _p256.n);
  final ecPrivateKey = _derSequence([
    _derInteger(BigInt.one),
    _derTlv(0x04, _fixed32(d)),
  ]);
  final pkcs8 = _derSequence([
    _derInteger(BigInt.zero),
    _derSequence([
      _derTlv(0x06, _oidEcPublicKey),
      _derTlv(0x06, _oidPrime256v1),
    ]),
    _derTlv(0x04, ecPrivateKey),
  ]);
  return b64UrlEncode(pkcs8);
}

const _oidEcPublicKey = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];
const _oidPrime256v1 = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07];

/// Reads the private scalar out of PKCS#8 or SEC1 DER.
BigInt _privateScalar(Uint8List der) {
  try {
    final outer = _DerReader(_DerReader(der).read(0x30));
    outer.read(0x02); // version
    if (outer.peekTag == 0x30) {
      // PKCS#8: AlgorithmIdentifier, then OCTET STRING wrapping SEC1.
      outer.read(0x30);
      return _sec1Scalar(outer.read(0x04));
    }
    // SEC1 ECPrivateKey: version 1, OCTET STRING d.
    return _toBigInt(outer.read(0x04));
  } on PasskeyException {
    rethrow;
  } catch (_) {
    throw PasskeyException('私钥格式无法识别（需要 P-256 PKCS#8 或 SEC1 DER）');
  }
}

BigInt _sec1Scalar(Uint8List der) {
  final r = _DerReader(_DerReader(der).read(0x30));
  r.read(0x02);
  return _toBigInt(r.read(0x04));
}

class _DerReader {
  _DerReader(this._b);
  final Uint8List _b;
  int _i = 0;

  int get peekTag => _i < _b.length ? _b[_i] : -1;

  Uint8List read(int tag) {
    if (_i >= _b.length || _b[_i] != tag) {
      throw PasskeyException('DER 结构不符');
    }
    _i++;
    var len = _b[_i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | _b[_i++];
      }
    }
    final out = Uint8List.sublistView(_b, _i, _i + len);
    _i += len;
    return out;
  }
}

BigInt _toBigInt(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _fixed32(BigInt v) {
  final out = Uint8List(32);
  var x = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  return out;
}

Uint8List _derLength(int len) {
  if (len < 0x80) return Uint8List.fromList([len]);
  final bytes = <int>[];
  var l = len;
  while (l > 0) {
    bytes.insert(0, l & 0xff);
    l >>= 8;
  }
  return Uint8List.fromList([0x80 | bytes.length, ...bytes]);
}

Uint8List _derTlv(int tag, List<int> value) =>
    Uint8List.fromList([tag, ..._derLength(value.length), ...value]);

Uint8List _derSequence(List<Uint8List> items) =>
    _derTlv(0x30, [for (final i in items) ...i]);

Uint8List _derInteger(BigInt v) {
  final bytes = <int>[];
  var x = v;
  while (x > BigInt.zero) {
    bytes.insert(0, (x & BigInt.from(0xff)).toInt());
    x >>= 8;
  }
  if (bytes.isEmpty) bytes.add(0);
  if (bytes.first & 0x80 != 0) bytes.insert(0, 0);
  return _derTlv(0x02, bytes);
}
