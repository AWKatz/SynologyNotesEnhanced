import 'package:flutter_test/flutter_test.dart';
import 'package:synologynotesenhanceds_enhanced/models/note.dart';
import 'package:synologynotesenhanceds_enhanced/models/notebook.dart';

/// Regression guards against real server objects captured in
/// docs/api/captures/Sync.Entry.Request.txt (Notebook list v2 / Note list v3).
/// These pin the field-name mapping (object_id/parent_id/brief/encrypt/stack/items).
void main() {
  test('Note.fromJson maps real Note-list v3 object', () {
    final json = {
      'archive': false,
      'brief': 'TEST',
      'category': 'note',
      'commit_msg': {'device': 'desktop', 'listable': true},
      'ctime': 1781482182,
      'encrypt': true,
      'mtime': 1781482398,
      'object_id': '1026_QF644RE9V50IT7EO6BU21NUFRG',
      'parent_id': '1026_DRUN13JRUT2B71QNCQMDE1FTS4',
      'perm': 'owner',
      'recycle': false,
      'title': 'New Note - Encrypted',
      'ver': 'e21ca4a7f11c520591cf87f963b6cd96776dad3b',
    };

    final note = Note.fromJson(json);
    expect(note.id, '1026_QF644RE9V50IT7EO6BU21NUFRG');
    expect(note.notebookId, '1026_DRUN13JRUT2B71QNCQMDE1FTS4');
    expect(note.excerpt, 'TEST');
    expect(note.isEncrypted, isTrue);
    expect(note.title, 'New Note - Encrypted');
    expect(note.createdAt?.millisecondsSinceEpoch, 1781482182 * 1000);
  });

  test('Notebook.fromJson maps real Notebook-list v2 object', () {
    final json = {
      'archive': false,
      'category': 'notebook',
      'ctime': 1699404446,
      'individual_shared': false,
      'items': [
        '1026_QF644RE9V50IT7EO6BU21NUFRG',
        '1026_52Q5HRNL2D4SN6HI8PJCA3B5UC',
        '1026_OMTEJUI4L50KBAGH78DVSNKMJG',
      ],
      'mtime': 1699404446,
      'object_id': '1026_DRUN13JRUT2B71QNCQMDE1FTS4',
      'preset': false,
      'stack': '',
      'title': 'Ideas',
    };

    final nb = Notebook.fromJson(json);
    expect(nb.id, '1026_DRUN13JRUT2B71QNCQMDE1FTS4');
    expect(nb.name, 'Ideas');
    expect(nb.noteCount, 3); // items.length
    expect(nb.shelfId, isNull); // empty stack → no shelf
    expect(nb.isArchived, isFalse);
    expect(nb.isShared, isFalse);
  });
}
