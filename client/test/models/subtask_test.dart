import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/subtask.dart';

void main() {
  group('Subtask', () {
    group('fromJson', () {
      test('完整字段正常解析', () {
        final sub = Subtask.fromJson({
          'id': 1,
          'task_id': 10,
          'title': '写测试',
          'is_completed': true,
          'sort_order': 2,
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(sub.id, 1);
        expect(sub.taskId, 10);
        expect(sub.title, '写测试');
        expect(sub.isCompleted, true);
        expect(sub.sortOrder, 2);
      });

      test('is_completed 缺失时默认 false', () {
        final sub = Subtask.fromJson({
          'id': 2,
          'task_id': 10,
          'title': '写代码',
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(sub.isCompleted, false);
      });

      test('sort_order 缺失时默认 0', () {
        final sub = Subtask.fromJson({
          'id': 3,
          'task_id': 10,
          'title': '部署',
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(sub.sortOrder, 0);
      });
    });
  });
}
