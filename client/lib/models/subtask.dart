class Subtask {
  final int id;
  final int taskId;
  final String title;
  final bool isCompleted;
  final int sortOrder;
  final DateTime createdAt;

  Subtask({
    required this.id,
    required this.taskId,
    required this.title,
    this.isCompleted = false,
    this.sortOrder = 0,
    required this.createdAt,
  });

  factory Subtask.fromJson(Map<String, dynamic> json) {
    return Subtask(
      id: json['id'],
      taskId: json['task_id'],
      title: json['title'],
      isCompleted: json['is_completed'] ?? false,
      sortOrder: json['sort_order'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
