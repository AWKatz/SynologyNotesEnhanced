import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;

/// Thrown when an encrypted note can't be decrypted with the supplied password.
class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'WrongPasswordException: incorrect note password';
}

/// Client-side decryption for NoteStation encrypted notes.
///
/// Verified from docs/api/captures/Note.Encrypt.Decrypt.txt: encrypted note
/// `content` is the OpenSSL/CryptoJS "Salted__" envelope (base64) — AES-256-CBC
/// with an MD5-based EVP_BytesToKey KDF — and the decrypted plaintext is prefixed
/// with [_magic] so the client can verify the password is correct. There is no
/// server-side decrypt API; the stock web client does exactly this in JS.
class NoteCrypto {
  /// Marker the stock client prepends to plaintext before encrypting.
  static const _magic = 'NoTeStAtIoNMaGic';
  static const _openSslHeader = 'Salted__';

  /// True if [content] looks like an encrypted note blob (base64 "Salted__").
  /// `U2FsdGVkX1` is the base64 prefix of the bytes `Salted__`.
  static bool isEncrypted(String content) =>
      content.startsWith('U2FsdGVkX1');

  /// Decrypts an encrypted note [content] blob with [password], returning the
  /// note's HTML. Throws [WrongPasswordException] if the password is wrong.
  static String decrypt(String content, String password) {
    final Uint8List raw;
    try {
      raw = base64.decode(content.trim());
    } on FormatException {
      throw const WrongPasswordException();
    }

    // Layout: "Salted__" (8) + salt (8) + ciphertext.
    if (raw.length < 16 ||
        utf8.decode(raw.sublist(0, 8), allowMalformed: true) !=
            _openSslHeader) {
      throw const WrongPasswordException();
    }
    final salt = raw.sublist(8, 16);
    final ciphertext = raw.sublist(16);

    final (key, iv) = _deriveKeyIv(utf8.encode(password), salt);

    final String plain;
    try {
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(key), mode: enc.AESMode.cbc), // PKCS7 padding (default)
      );
      plain = encrypter.decrypt(enc.Encrypted(ciphertext), iv: enc.IV(iv));
    } catch (_) {
      // Bad PKCS#7 padding ⇒ wrong key ⇒ wrong password.
      throw const WrongPasswordException();
    }

    if (!plain.startsWith(_magic)) throw const WrongPasswordException();
    return plain.substring(_magic.length);
  }

  /// OpenSSL EVP_BytesToKey (MD5, 1 iteration): derives a 32-byte key + 16-byte
  /// IV from [password] and [salt], matching `openssl enc -aes-256-cbc -md md5`.
  static (Uint8List, Uint8List) _deriveKeyIv(
      List<int> password, List<int> salt) {
    const keyLen = 32, ivLen = 16;
    final out = <int>[];
    var prev = <int>[];
    while (out.length < keyLen + ivLen) {
      prev = crypto.md5.convert([...prev, ...password, ...salt]).bytes;
      out.addAll(prev);
    }
    return (
      Uint8List.fromList(out.sublist(0, keyLen)),
      Uint8List.fromList(out.sublist(keyLen, keyLen + ivLen)),
    );
  }
}
