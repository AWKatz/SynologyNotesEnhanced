class Notebook {
  final String id;
  final String name;
  final String? shelfId; // stack_id in the API
  final int noteCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isShared;
  final bool isArchived;

  const Notebook({
    required this.id,
    required this.name,
    this.shelfId,
    this.noteCount = 0,
    this.createdAt,
    this.updatedAt,
    this.isShared = false,
    this.isArchived = false,
  });

  factory Notebook.fromJson(Map<String, dynamic> json) {
    // Real API (Notebook list v2) returns `object_id`; older code/mock may use notebook_id/id.
    final id =
        (json['object_id'] ?? json['notebook_id'] ?? json['id'])?.toString() ?? '';
    // API uses `title`; local mock may use `name`
    final name = json['title'] as String? ?? json['name'] as String? ?? 'Untitled';

    // Real API: shelf grouping is `stack` (title string, "" = none).
    final stack = json['stack'] as String?;
    final shelfId = (stack != null && stack.isNotEmpty)
        ? stack
        : json['stack_id']?.toString();

    // Real API: note count is the length of `items` (ordered note ids).
    final items = json['items'] as List<dynamic>?;
    final noteCount = items?.length ?? json['note_count'] as int? ?? 0;

    return Notebook(
      id: id,
      name: name,
      shelfId: shelfId,
      noteCount: noteCount,
      createdAt: json['ctime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['ctime'] as int) * 1000)
          : null,
      updatedAt: json['mtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['mtime'] as int) * 1000)
          : null,
      // Real API: `individual_shared` and `archive`.
      isShared: json['individual_shared'] as bool? ?? json['shared'] as bool? ?? false,
      isArchived: json['archive'] as bool? ?? json['archived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'notebook_id': id,
        'title': name,
        'stack_id': shelfId,
        'note_count': noteCount,
        'shared': isShared,
        'archived': isArchived,
      };

  Notebook copyWith({
    String? id,
    String? name,
    String? shelfId,
    int? noteCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isShared,
    bool? isArchived,
  }) {
    return Notebook(
      id: id ?? this.id,
      name: name ?? this.name,
      shelfId: shelfId ?? this.shelfId,
      noteCount: noteCount ?? this.noteCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isShared: isShared ?? this.isShared,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Notebook && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
