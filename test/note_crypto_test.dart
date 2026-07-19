import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synologynotesenhanceds_enhanced/core/crypto/note_crypto.dart';

/// Pins client-side note decryption against a REAL encrypted blob captured from
/// the NAS (docs/api/captures/Note.Encrypt.Decrypt.txt). Password is "12345".
void main() {
  final blob =
      File('test/fixtures/encrypted_note_12345.b64').readAsStringSync();

  test('isEncrypted detects the Salted__ base64 prefix', () {
    expect(NoteCrypto.isEncrypted(blob), isTrue);
    expect(NoteCrypto.isEncrypted('<p>plain note</p>'), isFalse);
  });

  test('decrypt with correct password returns the note HTML (magic stripped)',
      () {
    final html = NoteCrypto.decrypt(blob, '12345');
    expect(html, startsWith('<h1>HEADING 1</h1>'));
    expect(html, contains('<table'));
    expect(html, isNot(contains('NoTeStAtIoNMaGic')));
  });

  test('decrypt with wrong password throws WrongPasswordException', () {
    expect(() => NoteCrypto.decrypt(blob, 'wrong'),
        throwsA(isA<WrongPasswordException>()));
  });

  test('decrypt on non-encrypted content throws', () {
    expect(() => NoteCrypto.decrypt('not base64 !!!', '12345'),
        throwsA(isA<WrongPasswordException>()));
  });

  test('encrypt then decrypt round-trips the original HTML', () {
    const html = '<h1>Round Trip</h1><p>secret body</p>';
    final blob = NoteCrypto.encrypt(html, 'hunter2');
    expect(NoteCrypto.isEncrypted(blob), isTrue);
    expect(NoteCrypto.decrypt(blob, 'hunter2'), equals(html));
  });

  test('encrypt output rejects the wrong password on decrypt', () {
    final blob = NoteCrypto.encrypt('<p>x</p>', 'right');
    expect(() => NoteCrypto.decrypt(blob, 'wrong'),
        throwsA(isA<WrongPasswordException>()));
  });

  test('encrypt uses a random salt on every call (never reuses IV/key)', () {
    final a = NoteCrypto.encrypt('<p>same</p>', 'pw');
    final b = NoteCrypto.encrypt('<p>same</p>', 'pw');
    expect(a, isNot(equals(b)));
  });
}
