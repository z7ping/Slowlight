class ReflectionEntry {
  final int id;
  final String entryType; // observation / reflection
  final String? questionId;
  final String? dimensionKey;
  final String content;
  final Map<String, dynamic> context;
  final DateTime createdAt;

  const ReflectionEntry({
    required this.id,
    required this.entryType,
    this.questionId,
    this.dimensionKey,
    required this.content,
    this.context = const {},
    required this.createdAt,
  });

  factory ReflectionEntry.fromJson(Map<String, dynamic> json) {
    final context = json['context'];
    return ReflectionEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      entryType: json['entry_type'] as String? ?? 'reflection',
      questionId: json['question_id'] as String?,
      dimensionKey: json['dimension_key'] as String?,
      content: json['content'] as String? ?? '',
      context: context is Map
          ? Map<String, dynamic>.from(context)
          : <String, dynamic>{},
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entry_type': entryType,
        'question_id': questionId,
        'dimension_key': dimensionKey,
        'content': content,
        'context': context,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}
