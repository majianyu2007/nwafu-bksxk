/// The Wisedu (金智) AuthServer password cipher, a port of the login page's
/// `encrypt.js` (`encryptPassword`) and of `wisedu_cas/crypto.py`:
///
///   base64(AES-CBC-PKCS7(key = pwdEncryptSalt, iv = random 16,
///                        plaintext = random 64 + password))
///
/// The random prefix and IV come from the site's own 48-character alphabet.
/// The server discards the prefix, so any random draw decrypts to the same
/// password; tests check the round trip rather than fixed bytes.
library;

import 'dart:convert';
import 'dart:math';

import 'package:pointycastle/export.dart';

const _aesChars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

String _casRandomString(int length, Random r) {
  final b = StringBuffer();
  for (var i = 0; i < length; i++) {
    b.write(_aesChars[r.nextInt(_aesChars.length)]);
  }
  return b.toString();
}

/// Encrypts [password] with the login page's [salt]. An empty salt returns
/// the password unchanged, as `encrypt.js` does.
///
/// Throws [ArgumentError] if a non-empty [salt] is not a valid AES key length
/// (16, 24, or 32 UTF-8 bytes).
String encryptCasPassword(String password, String salt, {Random? random}) {
  final key = salt.trim();
  if (key.isEmpty) return password;
  final keyBytes = utf8.encode(key);
  if (keyBytes.length != 16 && keyBytes.length != 24 && keyBytes.length != 32) {
    throw ArgumentError.value(
      keyBytes.length,
      'salt',
      'AES key must be 16, 24, or 32 bytes',
    );
  }
  final r = random ?? Random.secure();
  final ivBytes = utf8.encode(_casRandomString(16, r));
  final plain = utf8.encode(_casRandomString(64, r) + password);
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(
      true,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV(KeyParameter(keyBytes), ivBytes),
        null,
      ),
    );
  return base64.encode(cipher.process(plain));
}
