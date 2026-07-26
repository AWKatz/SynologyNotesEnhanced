import '../core/crypto/note_crypto.dart';

class Note {
  final String id;
  final String notebookId;
  final String title;
  final String content;
  final String? excerpt;
  final List<String> tags; // tag IDs from API; resolved to names via TagsProvider
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isPinned;
  final bool isFavorite;
  final bool isEncrypted;
  // Server revision (sha1) — required by Note.set for optimistic concurrency.
  final String? ver;
  // Short id used in the note's image-attachment download URL — see
  // SynologyApiClient.noteImageUri. Not the same as [id] (which is the
  // longer `object_id`).
  final String? linkId;
  // Keyed by attachment ref → {md5,name,ext,width,height,size,...}. Used to
  // resolve a saved <img ref="..."> tag to a real downloadable URL.
  final Map<String, dynamic> attachment;

  const Note({
    required this.id,
    required this.notebookId,
    required this.title,
    this.content = '',
    this.excerpt,
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
    this.isPinned = false,
    this.isFavorite = false,
    this.isEncrypted = false,
    this.ver,
    this.linkId,
    this.attachment = const {},
  });

  /// Never derived from `content` or `excerpt` for encrypted notes — those may
  /// be the raw ciphertext blob or (if the server ever fails to scrub it) a
  /// stale plaintext `brief`. Never show either without the password.
  String get displayExcerpt {
    if (isEncrypted || NoteCrypto.isEncrypted(content)) return '';
    if (excerpt != null && excerpt!.isNotEmpty) return excerpt!;
    final plain = content.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
    return plain.length > 120 ? '${plain.substring(0, 120)}…' : plain;
  }

  bool get hasContent => content.isNotEmpty;

  factory Note.fromJson(Map<String, dynamic> json) {
    // Real API (Note list v3) returns `object_id`; older code/mock may use note_id/id.
    final id =
        (json['object_id'] ?? json['note_id'] ?? json['id'])?.toString() ?? '';

    final rawTags = json['tag'] as List<dynamic>?;
    final tags = rawTags?.map((t) => t.toString()).toList() ?? <String>[];

    return Note(
      id: id,
      // Real API: owning notebook is `parent_id`.
      notebookId:
          (json['parent_id'] ?? json['notebook_id'])?.toString() ?? '',
      title: json['title'] as String? ?? 'Untitled Note',
      content: json['content'] as String? ?? '',
      // Real API: plain-text preview is `brief`.
      excerpt: json['brief'] as String? ?? json['snippet'] as String?,
      tags: tags,
      createdAt: json['ctime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['ctime'] as int) * 1000)
          : null,
      updatedAt: json['mtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['mtime'] as int) * 1000)
          : null,
      isPinned: json['pinned'] as bool? ?? false,
      isFavorite: json['is_starred'] as bool? ?? json['favorite'] as bool? ?? false,
      // Real API: encrypted flag is `encrypt`.
      isEncrypted: json['encrypt'] as bool? ?? json['is_encrypted'] as bool? ?? false,
      ver: json['ver'] as String?,
      linkId: json['link_id'] as String?,
      attachment: (json['attachment'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'note_id': id,
        'notebook_id': notebookId,
        'title': title,
        'content': content,
        'snippet': excerpt,
        'tag': tags,
        'is_starred': isFavorite,
        'is_encrypted': isEncrypted,
        'link_id': linkId,
        'attachment': attachment,
      };

  Note copyWith({
    String? id,
    String? notebookId,
    String? title,
    String? content,
    String? excerpt,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    bool? isFavorite,
    bool? isEncrypted,
    String? ver,
    String? linkId,
    Map<String, dynamic>? attachment,
  }) {
    return Note(
      id: id ?? this.id,
      notebookId: notebookId ?? this.notebookId,
      title: title ?? this.title,
      content: content ?? this.content,
      excerpt: excerpt ?? this.excerpt,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      ver: ver ?? this.ver,
      linkId: linkId ?? this.linkId,
      attachment: attachment ?? this.attachment,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Note && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
