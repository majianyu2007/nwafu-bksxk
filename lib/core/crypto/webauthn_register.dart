/// A software WebAuthn authenticator for binding *this app* as a 生物识别
/// device on the school's AuthServer, so later sign-ins use the key kept in
/// this device's secure storage (unlocked by fingerprint / Face ID) instead
/// of a password.
///
/// The personal centre's 添加设备 calls `navigator.credentials.create()` with
/// the server's `publicKeyCredentialCreationOptions` and posts the result to
/// `accountSecurity/finishRegister`. [buildRegistrationCredential] produces
/// the same object: a fresh P-256 key, `authenticatorData` with attested
/// credential data, and an attestation object in the `none` format (or
/// `packed` self-attestation, signed by the credential key itself).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

import 'passkey.dart';

/// Attestation formats the builder can produce.
enum AttestationFormat { none, packedSelf }

/// The result of a registration: what to post, and what to keep.
class DeviceRegistration {
  DeviceRegistration({required this.credential, required this.response});

  /// The credential to store (its [PasskeyCredential.deviceBindingId] is
  /// filled in from the server's answer by the caller).
  final PasskeyCredential credential;

  /// The `credential` object for `finishRegister`.
  final Map<String, dynamic> response;
}

/// Builds the `navigator.credentials.create()` result for [options]
/// (`publicKeyCredentialCreationOptions` as the server sent it: base64url
/// strings for `challenge` and `user.id`).
DeviceRegistration buildRegistrationCredential({
  required Map<String, dynamic> options,
  required String origin,
  AttestationFormat format = AttestationFormat.none,
  Random? random,
}) {
  final r = random ?? Random.secure();
  final rp = options['rp'];
  final rpId = (rp is Map ? rp['id'] : null)?.toString() ?? Uri.parse(origin).host;
  final challenge = options['challenge']?.toString() ?? '';
  if (challenge.isEmpty) {
    throw PasskeyException('服务器未提供注册挑战');
  }
  final params = options['pubKeyCredParams'];
  if (params is List &&
      params.isNotEmpty &&
      !params.any((p) => p is Map && '${p['alg']}' == '-7')) {
    throw PasskeyException('服务器不接受 ES256 (P-256) 密钥');
  }
  final user = options['user'];
  final userHandle = (user is Map ? user['id'] : null)?.toString() ?? '';

  final keyValue = generatePasskeyKey(random: r);
  final q = publicPointOf(keyValue);
  final credId = Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));

  final clientData = utf8.encode(jsonEncode({
    'type': 'webauthn.create',
    'challenge': challenge.replaceAll('=', ''),
    'origin': origin,
    'crossOrigin': false,
  }));

  final cose = cborEncode({
    1: 2, // kty: EC2
    3: -7, // alg: ES256
    -1: 1, // crv: P-256
    -2: _coord(q.x!.toBigInteger()!),
    -3: _coord(q.y!.toBigInteger()!),
  });
  final authData = Uint8List.fromList([
    ...hash.sha256.convert(utf8.encode(rpId)).bytes,
    0x45, // UP | UV | AT
    0, 0, 0, 0, // signCount
    ...List.filled(16, 0), // AAGUID
    credId.length >> 8, credId.length & 0xff,
    ...credId,
    ...cose,
  ]);

  final Map<String, Object> attStmt;
  if (format == AttestationFormat.packedSelf) {
    final signed = Uint8List.fromList(
        [...authData, ...hash.sha256.convert(clientData).bytes]);
    attStmt = {
      'alg': -7,
      'sig': signP256(privateScalarOf(keyValue), signed, random: r),
    };
  } else {
    attStmt = {};
  }
  final attestationObject = cborEncode({
    'fmt': format == AttestationFormat.none ? 'none' : 'packed',
    'attStmt': attStmt,
    'authData': authData,
  });

  final id = b64UrlEncode(credId);
  return DeviceRegistration(
    credential: PasskeyCredential(
      credentialId: id,
      keyValue: keyValue,
      rpId: rpId,
      deviceBindingId: '',
      userHandle: userHandle,
    ),
    response: {
      'type': 'public-key',
      'id': id,
      'response': {
        'attestationObject': b64UrlEncode(attestationObject),
        'clientDataJSON': b64UrlEncode(clientData),
      },
      'clientExtensionResults': <String, dynamic>{},
    },
  );
}

Uint8List _coord(BigInt v) {
  final out = Uint8List(32);
  var x = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Minimal CBOR (RFC 8949) encoder: ints, byte/text strings, lists, maps.
// Map entries keep insertion order, which callers make canonical.
// ---------------------------------------------------------------------------

Uint8List cborEncode(Object? value) {
  final out = BytesBuilder();
  _cbor(out, value);
  return out.toBytes();
}

void _head(BytesBuilder out, int major, int n) {
  final m = major << 5;
  if (n < 24) {
    out.addByte(m | n);
  } else if (n < 0x100) {
    out
      ..addByte(m | 24)
      ..addByte(n);
  } else if (n < 0x10000) {
    out
      ..addByte(m | 25)
      ..add([n >> 8, n & 0xff]);
  } else {
    out
      ..addByte(m | 26)
      ..add([n >> 24 & 0xff, n >> 16 & 0xff, n >> 8 & 0xff, n & 0xff]);
  }
}

void _cbor(BytesBuilder out, Object? v) {
  switch (v) {
    case final int i when i >= 0:
      _head(out, 0, i);
    case final int i:
      _head(out, 1, -1 - i);
    case final Uint8List b:
      _head(out, 2, b.length);
      out.add(b);
    case final String s:
      final b = utf8.encode(s);
      _head(out, 3, b.length);
      out.add(b);
    case final List l:
      _head(out, 4, l.length);
      for (final e in l) {
        _cbor(out, e);
      }
    case final Map m:
      _head(out, 5, m.length);
      m.forEach((k, e) {
        _cbor(out, k);
        _cbor(out, e);
      });
    case final bool b:
      out.addByte(b ? 0xf5 : 0xf4);
    case null:
      out.addByte(0xf6);
    default:
      throw ArgumentError('CBOR: unsupported ${v.runtimeType}');
  }
}

/// Decodes CBOR produced by [cborEncode]; tests use it to inspect output.
Object? cborDecode(Uint8List bytes) => _CborReader(bytes).read();

class _CborReader {
  _CborReader(this._b);
  final Uint8List _b;
  int _i = 0;

  int _arg(int info) {
    if (info < 24) return info;
    final n = switch (info) { 24 => 1, 25 => 2, 26 => 4, _ => 8 };
    var v = 0;
    for (var k = 0; k < n; k++) {
      v = (v << 8) | _b[_i++];
    }
    return v;
  }

  Object? read() {
    final ib = _b[_i++];
    final major = ib >> 5, info = ib & 0x1f;
    if (major == 7) {
      return switch (info) { 20 => false, 21 => true, _ => null };
    }
    final n = _arg(info);
    switch (major) {
      case 0:
        return n;
      case 1:
        return -1 - n;
      case 2:
        final v = Uint8List.sublistView(_b, _i, _i + n);
        _i += n;
        return v;
      case 3:
        final v = utf8.decode(_b.sublist(_i, _i + n));
        _i += n;
        return v;
      case 4:
        return [for (var k = 0; k < n; k++) read()];
      case 5:
        final m = <Object?, Object?>{};
        for (var k = 0; k < n; k++) {
          final key = read();
          m[key] = read();
        }
        return m;
    }
    throw FormatException('CBOR major $major');
  }
}

/// Re-exported for tests that need to check signatures over registrations.
ECPoint registrationPublicKey(PasskeyCredential c) => publicPointOf(c.keyValue);
