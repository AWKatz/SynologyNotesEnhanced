/// A saved revision of a note. Verified (`.docs/reference/Version restore*.har`):
/// `SYNO.NoteStation.Note.Version list` v2 returns these; `version` (a sha,
/// confusingly not named `ver`) is the same value `Note.get`'s own `ver`
/// param and `Note.Version restore` both key on.
class NoteVersion {
  final int id;
  final String ver;
  final String author;
  final DateTime? mtime;

  const NoteVersion({
    required this.id,
    required this.ver,
    required this.author,
    this.mtime,
  });

  factory NoteVersion.fromJson(Map<String, dynamic> json) {
    return NoteVersion(
      id: json['id'] as int? ?? 0,
      ver: json['version'] as String? ?? '',
      author: json['author'] as String? ?? '',
      mtime: json['mtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['mtime'] as int) * 1000)
          : null,
    );
  }
}
