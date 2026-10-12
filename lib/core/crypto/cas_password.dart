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
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const _aesChars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

String casRandomString(int length, [Random? random]) {
  final r = random ?? Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < length; i++) {
    b.write(_aesChars[r.nextInt(_aesChars.length)]);
  }
  return b.toString();
}

/// Encrypts [password] with the login page's [salt]. An empty salt returns
/// the password unchanged, as `encrypt.js` does.
String encryptCasPassword(String password, String salt, {Random? random}) {
  final key = salt.trim();
  if (key.isEmpty) return password;
  final iv = casRandomString(16, random);
  final plain = utf8.encode(casRandomString(64, random) + password);
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(
      true,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(key))),
            Uint8List.fromList(utf8.encode(iv))),
        null,
      ),
    );
  return base64.encode(cipher.process(Uint8List.fromList(plain)));
}

/// Decrypts a value produced by [encryptCasPassword] given the IV it used.
/// Only tests need this; the server does the real decryption.
String decryptCasPasswordForTest(String encoded, String salt, String iv) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
    ..init(
      false,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV(
            KeyParameter(Uint8List.fromList(utf8.encode(salt.trim()))),
            Uint8List.fromList(utf8.encode(iv))),
        null,
      ),
    );
  final plain = utf8.decode(cipher.process(base64.decode(encoded)));
  return plain.substring(64);
}
