import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/note.dart';
import '../../models/notebook.dart';

/// Parsed contents of a NoteStation `.nsx` export.
///
/// Structure verified in docs/api/captures/NSX-format.md: a ZIP whose entries
/// are named by `object_id`, plus a `config.json` manifest and `file_*`
/// attachment blobs. Attachment bytes (incl. the not-yet-decoded `Saltv2__`
/// encrypted ones) are carried opaquely so a decode→encode round-trips them.
class NsxBundle {
  final List<Notebook> notebooks;
  final List<Note> notes;

  /// Attachment entry name (`file_..._<md5>`) → raw bytes.
  final Map<String, Uint8List> attachments;

  /// Original note/notebook JSON, keyed by object_id, preserved for fields our
  /// models don't carry (attachment metadata, brief, geo) on re-export.
  final Map<String, Map<String, dynamic>> rawObjects;

  const NsxBundle({
    required this.notebooks,
    required this.notes,
    this.attachments = const {},
    this.rawObjects = const {},
  });
}

/// Reads and writes NoteStation `.nsx` (ZIP) export bundles.
class NsxCodec {
  /// Decodes `.nsx` [bytes] into a [NsxBundle]. Throws [FormatException] if the
  /// archive isn't a valid nsx (missing/!config.json).
  static NsxBundle decode(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Not a valid .nsx (ZIP) file: $e');
    }

    final entries = <String, Uint8List>{};
    for (final f in archive.files) {
      if (f.isFile) entries[f.name] = Uint8List.fromList(f.content as List<int>);
    }

    final configBytes = entries['config.json'];
    if (configBytes == null) {
      throw const FormatException('Missing config.json — not a NoteStation .nsx');
    }
    final config = jsonDecode(utf8.decode(configBytes)) as Map<String, dynamic>;

    final notebookIds =
        (config['notebook'] as List<dynamic>? ?? []).cast<String>();
    final noteIds = (config['note'] as List<dynamic>? ?? []).cast<String>();

    final raw = <String, Map<String, dynamic>>{};
    final notebooks = <Notebook>[];
    final notes = <Note>[];

    Map<String, dynamic>? readJson(String id) {
      final b = entries[id];
      if (b == null) return null;
      final json = jsonDecode(utf8.decode(b)) as Map<String, dynamic>;
      // The object_id lives in the entry NAME, not the JSON — inject it so the
      // model factories (which read object_id) resolve the id correctly.
      json['object_id'] = id;
      raw[id] = json;
      return json;
    }

    for (final id in notebookIds) {
      final json = readJson(id);
      if (json != null) notebooks.add(Notebook.fromJson(json));
    }
    for (final id in noteIds) {
      final json = readJson(id);
      if (json != null) notes.add(Note.fromJson(json));
    }

    final attachments = <String, Uint8List>{};
    for (final entry in entries.entries) {
      if (entry.key.startsWith('file_')) attachments[entry.key] = entry.value;
    }

    return NsxBundle(
      notebooks: notebooks,
      notes: notes,
      attachments: attachments,
      rawObjects: raw,
    );
  }

  /// Encodes [bundle] back into `.nsx` ZIP bytes. Notes/notebooks are written
  /// from their original JSON when available (lossless), else synthesized from
  /// the models.
  static Uint8List encode(NsxBundle bundle) {
    final archive = Archive();

    void addJson(String name, Map<String, dynamic> json) {
      final data = utf8.encode(jsonEncode(json));
      archive.addFile(ArchiveFile(name, data.length, data));
    }

    final noteIds = <String>[];
    final notebookIds = <String>[];

    for (final nb in bundle.notebooks) {
      notebookIds.add(nb.id);
      addJson(nb.id, _notebookJson(nb, bundle.rawObjects[nb.id]));
    }
    for (final note in bundle.notes) {
      noteIds.add(note.id);
      addJson(note.id, _noteJson(note, bundle.rawObjects[note.id]));
    }

    addJson('config.json', {
      'note': noteIds,
      'notebook': notebookIds,
      'shortcut': {'id': <String>[], 'stack': <String>[], 'tag': <String>[]},
      'todo': <String>[],
    });

    bundle.attachments.forEach((name, data) {
      archive.addFile(ArchiveFile(name, data.length, data));
    });

    final out = ZipEncoder().encode(archive) ?? <int>[];
    return Uint8List.fromList(out);
  }

  static int? _epochSeconds(DateTime? dt) =>
      dt == null ? null : dt.millisecondsSinceEpoch ~/ 1000;

  static Map<String, dynamic> _notebookJson(
      Notebook nb, Map<String, dynamic>? raw) {
    final json = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(raw)
      ..remove('object_id');
    json['category'] = 'notebook';
    json['title'] = nb.name;
    json['stack'] = nb.shelfId ?? '';
    json['ctime'] ??= _epochSeconds(nb.createdAt);
    json['mtime'] ??= _epochSeconds(nb.updatedAt);
    return json;
  }

  static Map<String, dynamic> _noteJson(Note note, Map<String, dynamic>? raw) {
    final json = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(raw)
      ..remove('object_id');
    json['parent_id'] = note.notebookId;
    json['title'] = note.title;
    json['content'] = note.content;
    json['tag'] = note.tags;
    json['encrypt'] = note.isEncrypted;
    if (note.excerpt != null) json['brief'] = note.excerpt;
    json['ctime'] ??= _epochSeconds(note.createdAt);
    json['mtime'] ??= _epochSeconds(note.updatedAt);
    json['attachment'] ??= <String, dynamic>{};
    return json;
  }
}
