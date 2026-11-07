import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit_log.dart';

void main() {
  test('P05 history must distinguish confirmed empty from missing payload', () {
    expect(HabitLog.parseHistory(const []), isEmpty);
    expect(() => HabitLog.parseHistory(null), throwsFormatException);
    expect(() => HabitLog.parseHistory(''), throwsFormatException);
    expect(() => HabitLog.parseHistory(const {'logs': []}),
        throwsFormatException);
    expect(() => HabitLog.parseHistory([null]), throwsFormatException);
    expect(() => HabitLog.parseHistory([{'id': 5}]),
        throwsFormatException);
  });

  test('P05 malformed history items are not silently discarded', () {
    const valid = {
      'id': -5, 'habit_id': -9, 'date': '2026-11-07',
      'duration_min': 10, 'note': '待云端同步',
    };
    final records = HabitLog.parseHistory([valid]);
    expect(records.single.id, -5);
    expect(records.single.habitId, -9);
    expect(records.single.durationMin, 10);
    expect(() => HabitLog.parseHistory([valid, 'not a log']),
        throwsFormatException);
    expect(() => HabitLog.parseHistory([
      {'id': 6, 'habit_id': 9, 'date': '2026-02-30'},
    ]), throwsFormatException);
    expect(() => HabitLog.parseHistory([
      {'id': 0, 'habit_id': 9, 'date': '2026-11-07'},
    ]), throwsFormatException);
  });

  test('P05 calendar month filtering agrees with server', () {
    for (final month in ['2026-01', '2026-11', '2026-12']) {
      expect(() => HabitLog.validateMonth(month), returnsNormally);
    }
    expect(() => HabitLog.validateMonth(null), returnsNormally);
    for (final month in ['2026-1', '2026-13', '2026', '2026-11%',
      '2026-00', '', '2026-11-07']) {
      expect(() => HabitLog.validateMonth(month), throwsFormatException);
    }
  });
}
