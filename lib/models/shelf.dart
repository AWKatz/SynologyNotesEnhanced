class Shelf {
  final String id;
  final String name;

  const Shelf({required this.id, required this.name});

  factory Shelf.fromJson(Map<String, dynamic> json) {
    return Shelf(
      id: json['stack_id']?.toString() ?? '',
      name: json['title'] as String? ?? 'Untitled Shelf',
    );
  }

  Map<String, dynamic> toJson() => {'stack_id': id, 'title': name};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Shelf && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
