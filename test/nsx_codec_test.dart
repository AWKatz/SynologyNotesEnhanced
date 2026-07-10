import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synologynotesenhanceds_enhanced/core/crypto/note_crypto.dart';
import 'package:synologynotesenhanceds_enhanced/core/nsx/nsx_codec.dart';

/// Pins the .nsx codec against a REAL DSM export
/// (test/fixtures/sample.nsx — notebook "TEST" with one encrypted note +
/// attachments). Format doc: docs/api/captures/NSX-format.md.
void main() {
  final bytes =
      Uint8List.fromList(File('test/fixtures/sample.nsx').readAsBytesSync());

  test('decode reads notebooks, notes, and attachments', () {
    final bundle = NsxCodec.decode(bytes);

    expect(bundle.notebooks, hasLength(1));
    expect(bundle.notebooks.single.name, 'TEST');

    expect(bundle.notes, hasLength(1));
    final note = bundle.notes.single;
    // id comes from the ZIP entry name, parent_id → notebookId.
    expect(note.id, '1026_V9LA3B1CE54HL8BFVNR2P839U4');
    expect(note.notebookId, '1026_KDLIK0SVJH7RJ4TA3NIFLV49P0');
    expect(note.notebookId, bundle.notebooks.single.id);
    expect(note.isEncrypted, isTrue);
    expect(note.title, contains('NEW NOTE'));

    // Encrypted note body is preserved as the raw Salted__ blob.
    expect(NoteCrypto.isEncrypted(note.content), isTrue);

    // Attachment blobs carried opaquely (3 file_* entries in the sample).
    expect(bundle.attachments.length, greaterThanOrEqualTo(2));
    expect(bundle.attachments.keys.every((k) => k.startsWith('file_')), isTrue);
  });

  test('decode→encode→decode round-trips structure and attachments', () {
    final original = NsxCodec.decode(bytes);
    final reencoded = NsxCodec.encode(original);
    final again = NsxCodec.decode(reencoded);

    expect(again.notebooks.single.id, original.notebooks.single.id);
    expect(again.notebooks.single.name, original.notebooks.single.name);
    expect(again.notes.single.id, original.notes.single.id);
    expect(again.notes.single.content, original.notes.single.content);
    expect(again.notes.single.isEncrypted, isTrue);
    expect(again.attachments.length, original.attachments.length);
    // Attachment bytes survive the round-trip unchanged.
    final key = original.attachments.keys.first;
    expect(again.attachments[key], original.attachments[key]);
  });

  test('decode rejects a non-nsx file', () {
    expect(() => NsxCodec.decode(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FormatException>()));
  });
}
