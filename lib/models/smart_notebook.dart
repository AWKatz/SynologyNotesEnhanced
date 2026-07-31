/// Search criteria for creating a Smart notebook. Verified param shape
/// (`.docs/reference/Smart Notebook*.har`, SYNO.NoteStation.Smart create
/// v1): `tag` is an array of `"<tagName>@<uid>"` strings, `tag_operator` is
/// `"and"`/`"or"`, `parent_id` is an array of notebook ids restricting the
/// search.
///
/// Only used to build the create request — `Smart.list` doesn't echo it
/// back and doesn't need to: opening a smart notebook is a real server-side
/// query keyed on the smart notebook's own id (see
/// NoteStationService.listNotesInSmart), not a client-side reapplication of
/// this criteria.
class SmartCriteria {
  final String? keyword;
  final String? innerTitle;
  final List<String> tagNames; // wire format is "<name>@<uid>", not tag id
  final String tagOperator; // "and" | "or"
  final List<String> notebookIds;

  const SmartCriteria({
    this.keyword,
    this.innerTitle,
    this.tagNames = const [],
    this.tagOperator = 'and',
    this.notebookIds = const [],
  });

  bool get isEmpty =>
      (keyword == null || keyword!.isEmpty) &&
      (innerTitle == null || innerTitle!.isEmpty) &&
      tagNames.isEmpty &&
      notebookIds.isEmpty;
}

class SmartNotebook {
  final String id;
  final String title;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SmartNotebook({
    required this.id,
    required this.title,
    this.createdAt,
    this.updatedAt,
  });

  factory SmartNotebook.fromJson(Map<String, dynamic> json) {
    return SmartNotebook(
      id: json['object_id']?.toString() ?? '',
      title: json['title'] as String? ?? 'Untitled',
      createdAt: json['ctime'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['ctime'] as int) * 1000)
          : null,
      updatedAt: json['mtime'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['mtime'] as int) * 1000)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SmartNotebook && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
