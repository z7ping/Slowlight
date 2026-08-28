import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/tag.dart';

void main() {
  group('Tag', () {
    group('fromJson', () {
      test('完整字段正常解析', () {
        final tag = Tag.fromJson({
          'id': 1,
          'name': '工作',
          'color': '#ff0000',
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(tag.id, 1);
        expect(tag.name, '工作');
        expect(tag.color, '#ff0000');
        expect(tag.createdAt, DateTime.parse('2026-04-15T10:00:00Z'));
      });

      test('color 缺失时使用默认值', () {
        final tag = Tag.fromJson({
          'id': 2,
          'name': '生活',
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(tag.color, '#0075de');
      });
    });

    group('toJson', () {
      test('序列化包含 name 和 color', () {
        final tag = Tag(
          id: 1,
          name: '工作',
          color: '#ff0000',
          createdAt: DateTime.parse('2026-04-15T10:00:00Z'),
        );

        final json = tag.toJson();
        expect(json['name'], '工作');
        expect(json['color'], '#ff0000');
        expect(json.containsKey('id'), false);
        expect(json.containsKey('created_at'), false);
      });
    });
  });
}
