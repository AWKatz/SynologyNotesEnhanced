class Tag {
  final String id;
  final String name;
  final int count;
  // Real API (Tag list v1): note object_ids carrying this tag. Note.list
  // doesn't return per-note tags, so this is the only way to know which
  // notes have which tags without fetching each note individually.
  final List<String> noteIds;

  const Tag({
    required this.id,
    required this.name,
    this.count = 0,
    this.noteIds = const [],
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    final items = json['items'] as List<dynamic>?;
    return Tag(
      id: json['tag_id']?.toString() ?? '',
      // Real API: tag display name is `title`; local mock may use `name`.
      name: json['title'] as String? ?? json['name'] as String? ?? '',
      count: json['count'] as int? ?? items?.length ?? 0,
      noteIds: items?.map((n) => n.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'tag_id': id,
        'title': name,
        'count': count,
        'items': noteIds,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
