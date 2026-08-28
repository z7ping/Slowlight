class TodoList {
  final int id;
  final int? serverId;
  final String name;
  final String icon;
  final String color;
  final bool isInbox;
  final DateTime createdAt;

  TodoList({
    required this.id,
    this.serverId,
    required this.name,
    this.icon = '📋',
    required this.color,
    this.isInbox = false,
    required this.createdAt,
  });

  factory TodoList.fromJson(Map<String, dynamic> json) {
    return TodoList(
      id: json['id'] is int ? json['id'] as int : int.parse(json['id'].toString()),
      serverId: json['server_id'] as int?,
      name: json['name'] as String,
      icon: (json['icon'] as String?) ?? '📋',
      color: (json['color'] as String?) ?? '#2196F3',
      isInbox: json['is_inbox'] is int
          ? (json['is_inbox'] as int) == 1
          : (json['is_inbox'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (serverId != null) 'server_id': serverId,
      'name': name,
      'icon': icon,
      'color': color,
      'is_inbox': isInbox,
      'created_at': createdAt.toIso8601String(),
    };
  }
}