import 'dart:typed_data';

import '../../models/note.dart';
import '../../repositories/local_notes_repository.dart';
import '../../repositories/notes_repository.dart';
import '../nsx/nsx_codec.dart';

/// Import/export glue between `.nsx` bundles and the app's repositories.
class NsxService {
  /// Parses [bytes] and imports the notebooks/notes into local offline storage
  /// (so formatting/decryption can be exercised without the NAS).
  /// Returns (#notebooks, #notes).
  static Future<(int, int)> importToLocal(Uint8List bytes) async {
    final bundle = NsxCodec.decode(bytes);
    return LocalNotesRepository().importBundle(bundle.notebooks, bundle.notes);
  }

  /// Builds a `.nsx` from everything in [repo] (every notebook and the full
  /// content of each of its notes). Encrypted bodies are exported as-is.
  static Future<Uint8List> exportFrom(NotesRepository repo) async {
    final notebooks = await repo.listNotebooks();
    final notes = <Note>[];
    for (final nb in notebooks) {
      final stubs = await repo.listNotes(notebookId: nb.id);
      for (final stub in stubs) {
        try {
          notes.add(await repo.getNote(stub.id));
        } catch (_) {
          notes.add(stub); // fall back to the list stub if full fetch fails
        }
      }
    }
    return NsxCodec.encode(NsxBundle(notebooks: notebooks, notes: notes));
  }
}
