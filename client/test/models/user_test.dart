import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/user.dart';

void main() {
  group('User', () {
    group('fromJson', () {
      test('完整字段正常解析', () {
        final user = User.fromJson({
          'id': 1,
          'username': 'z7ping',
          'email': 'z@test.com',
          'nickname': '小明',
          'avatar': null,
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(user.id, 1);
        expect(user.username, 'z7ping');
        expect(user.email, 'z@test.com');
        expect(user.nickname, '小明');
        expect(user.avatar, isNull);
      });

      test('nickname 缺失时回退到 username', () {
        final user = User.fromJson({
          'id': 2,
          'username': 'test',
          'email': 't@test.com',
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(user.nickname, 'test');
      });
    });

    group('toJson', () {
      test('序列化包含所有字段', () {
        final user = User(
          id: 1,
          username: 'z7ping',
          email: 'z@test.com',
          nickname: '小明',
          avatar: null,
          createdAt: DateTime.parse('2026-04-15T10:00:00Z'),
        );

        final json = user.toJson();
        expect(json['id'], 1);
        expect(json['username'], 'z7ping');
        expect(json['email'], 'z@test.com');
        expect(json['nickname'], '小明');
        expect(json['avatar'], isNull);
        expect(json['created_at'], '2026-04-15T10:00:00.000Z');
      });
    });
  });
}
