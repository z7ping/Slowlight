import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/todo_list.dart';

void main() {
  group('TodoList', () {
    group('fromJson', () {
      test('完整字段正常解析', () {
        final list = TodoList.fromJson({
          'id': 1,
          'name': '工作',
          'color': '#2196F3',
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(list.id, 1);
        expect(list.name, '工作');
        expect(list.color, '#2196F3');
        expect(list.createdAt, DateTime.parse('2026-04-15T10:00:00Z'));
      });

      test('color 缺失时使用默认值 #2196F3', () {
        final list = TodoList.fromJson({
          'id': 2,
          'name': '学习',
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(list.color, '#2196F3');
      });
    });
  });
}
