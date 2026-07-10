class Tag {
  final String id;
  final String name;
  final int count;

  const Tag({required this.id, required this.name, this.count = 0});

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['tag_id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      count: json['count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'tag_id': id,
        'name': name,
        'count': count,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
