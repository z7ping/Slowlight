import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit_timezone_policy.dart';
import 'package:slowlight/models/user.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  test('P05 cloud account timezone survives auth cache round-trip', () {
    final user = User.fromJson({
      'id': 12, 'username': 'reader', 'email': 'r@example.org',
      'nickname': '阅读', 'timezone': 'America/Los_Angeles',
      'created_at': '2026-11-08T01:00:00Z',
    });
    expect(user.timezone, 'America/Los_Angeles');
    expect(User.fromJson(user.toJson()).timezone, 'America/Los_Angeles');
    final legacy = User.fromJson({
      'id': 13, 'username': 'old', 'email': 'o@example.org',
      'created_at': '2026-11-08T01:00:00Z',
    });
    expect(legacy.timezone, isNull);
  });

  test('P05 missing or invalid account zone blocks offline writes', () {
    expect(() => HabitTimezonePolicy.requireCompatibleDeviceCalendar(null),
        throwsA(isA<HabitTimezoneMismatch>()));
    expect(() => HabitTimezonePolicy.requireCompatibleDeviceCalendar(''),
        throwsA(isA<HabitTimezoneMismatch>()));
    expect(() => HabitTimezonePolicy.requireCompatibleDeviceCalendar(
      'Not/A_Real_Zone'), throwsA(isA<HabitTimezoneMismatch>()));
  });

  test('P05 matching account calendar stays recordable', () {
    tzdata.initializeTimeZones();
    final location = tz.getLocation('America/Los_Angeles');
    expect(() => HabitTimezonePolicy.requireCompatibleDeviceCalendar(
      'America/Los_Angeles',
      now: DateTime.utc(2026, 11, 8, 1),
      recordDate: '2026-03-08',
      deviceOffsetAt: (instant) =>
          tz.TZDateTime.from(instant, location).timeZoneOffset,
    ), returnsNormally);
  });

  test('P05 equal winter offset is insufficient if DST differs', () {
    expect(() => HabitTimezonePolicy.requireCompatibleDeviceCalendar(
      'America/Los_Angeles',
      now: DateTime.utc(2026, 1, 15, 12),
      deviceOffsetAt: (_) => const Duration(hours: -8),
    ), throwsA(isA<HabitTimezoneMismatch>()));
  });

  test('P05 a fixed matching calendar is accepted', () {
    expect(() => HabitTimezonePolicy.requireCompatibleDeviceCalendar(
      'Asia/Shanghai',
      now: DateTime.utc(2026, 11, 8, 1),
      deviceOffsetAt: (_) => const Duration(hours: 8),
    ), returnsNormally);
  });
}
