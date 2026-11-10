import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';

void main() {
  group('Habit', () {
    group('fromJson', () {
      test('完整字段正常解析', () {
        final habit = Habit.fromJson({
          'id': 1,
          'user_id': 10,
          'name': '早起',
          'icon': '🌅',
          'color': '#ff0000',
          'frequency': 'daily',
          'target_days': 30,
          'streak_count': 5,
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(habit.id, 1);
        expect(habit.userId, 10);
        expect(habit.name, '早起');
        expect(habit.icon, '🌅');
        expect(habit.color, '#ff0000');
        expect(habit.frequency, 'daily');
        expect(habit.targetDays, 30);
        expect(habit.streakCount, 5);
      });

      test('可选字段缺失时使用默认值', () {
        final habit = Habit.fromJson({
          'id': 2,
          'user_id': 10,
          'name': '阅读',
          'created_at': '2026-04-15T10:00:00Z',
        });

        expect(habit.icon, '✅');
        expect(habit.color, '#52c41a');
        expect(habit.frequency, 'daily');
        expect(habit.targetDays, 0);
        expect(habit.streakCount, 0);
      });
    });

    group('frequencyText', () {
      test('daily → 每天', () {
        final habit = Habit.fromJson({
          'id': 1, 'user_id': 1, 'name': 'x', 'frequency': 'daily',
          'created_at': '2026-04-15T10:00:00Z',
        });
        expect(habit.frequencyText, '每天');
      });

      test('weekly → 每周', () {
        final habit = Habit.fromJson({
          'id': 1, 'user_id': 1, 'name': 'x', 'frequency': 'weekly',
          'created_at': '2026-04-15T10:00:00Z',
        });
        expect(habit.frequencyText, '每周');
      });

      test('monthly → 每月', () {
        final habit = Habit.fromJson({
          'id': 1, 'user_id': 1, 'name': 'x', 'frequency': 'monthly',
          'created_at': '2026-04-15T10:00:00Z',
        });
        expect(habit.frequencyText, '每月');
      });

      test('旧 custom 缺少真实 V3 规则时不展示占位枚举', () {
        final habit = Habit.fromJson({
          'id': 1, 'user_id': 1, 'name': 'x', 'frequency': 'custom',
          'created_at': '2026-04-15T10:00:00Z',
        });
        expect(habit.frequencyText, isEmpty);
      });

      test('残缺 custom V3 规则不伪造成每天或默认时间窗口', () {
        final partial = Habit.fromJson({
          'id': 2, 'user_id': 1, 'name': 'x', 'frequency': 'custom',
          'schedule_rule': {'version': 1},
          'created_at': '2026-04-15T10:00:00Z',
        });
        expect(partial.frequencyText, isEmpty);
        final missingHourMode = Habit.fromJson({
          'id': 3, 'user_id': 1, 'name': 'x', 'frequency': 'custom',
          'schedule_rule': {
            'kind': 'interval', 'unit': 'hour', 'every': 2,
            'anchor_date': '2026-01-01',
          },
          'created_at': '2026-04-15T10:00:00Z',
        });
        expect(missingHourMode.frequencyText, isEmpty);
      });
    });
  });
}
