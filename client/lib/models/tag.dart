class Tag {
  final int id;
  final String name;
  final String color;
  final DateTime createdAt;

  Tag({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'],
      name: json['name'],
      color: json['color'] ?? '#0075de',
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'color': color,
    };
  }
}
