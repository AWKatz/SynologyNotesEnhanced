/// A NoteStation to-do item. Verified against `.docs/reference/To Do list
/// capture*.har` (SYNO.NoteStation.Todo v2 list/create/set, v1 delete) and
/// `.docs/reference/Substasks*.har` (subtask create/list).
class Todo {
  final String id;
  final String title;
  final String comment;
  final bool done;
  final bool star;
  // -1 = no priority set. The stock client's UI buckets this into low/
  // medium/high, but the capture only ever showed a raw int (300) — no
  // capture of the bucket boundaries yet, so this stays a raw int for now.
  final int priority;
  final DateTime? dueDate;
  final String? noteId;
  final String? parentId;
  // VERIFIED (Substasks*.har): a parent's own `items` field is an array of
  // subtask object_id STRINGS, not nested todo objects — fetch each
  // subtask's own fields via NoteStationService.listTodos(parentId: id).
  // (An earlier version of this model wrongly assumed nested objects here,
  // which would have crashed parsing any real todo with subtasks — every
  // capture until this one only ever showed an empty `items: []`.)
  final List<String> subtaskIds;

  const Todo({
    required this.id,
    required this.title,
    this.comment = '',
    this.done = false,
    this.star = false,
    this.priority = -1,
    this.dueDate,
    this.noteId,
    this.parentId,
    this.subtaskIds = const [],
  });

  factory Todo.fromJson(Map<String, dynamic> json) {
    final dueDateEpoch = json['due_date'] as int?;
    final items = json['items'] as List<dynamic>?;
    final noteId = json['note_id'] as String?;
    final parentId = json['parent_id'] as String?;

    return Todo(
      id: json['object_id']?.toString() ?? '',
      title: json['title'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      star: json['star'] as bool? ?? false,
      priority: json['priority'] as int? ?? -1,
      dueDate: (dueDateEpoch != null && dueDateEpoch > 0)
          ? DateTime.fromMillisecondsSinceEpoch(dueDateEpoch * 1000)
          : null,
      noteId: (noteId != null && noteId.isNotEmpty) ? noteId : null,
      parentId: (parentId != null && parentId.isNotEmpty) ? parentId : null,
      subtaskIds: items?.map((j) => j.toString()).toList() ?? const [],
    );
  }

  Todo copyWith({
    String? title,
    String? comment,
    bool? done,
    bool? star,
    int? priority,
    DateTime? dueDate,
  }) {
    return Todo(
      id: id,
      title: title ?? this.title,
      comment: comment ?? this.comment,
      done: done ?? this.done,
      star: star ?? this.star,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      noteId: noteId,
      parentId: parentId,
      subtaskIds: subtaskIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Todo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
