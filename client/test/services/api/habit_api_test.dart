import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/api/habit_api.dart';

void main() {
  group('HabitApi', () {
    test('should have getHabits method', () {
      expect(HabitApi.getHabits, isA<Function>());
    });

    test('should have createHabit method', () {
      expect(HabitApi.createHabit, isA<Function>());
    });

    test('should have checkInHabit method', () {
      expect(HabitApi.checkInHabit, isA<Function>());
    });

    test('should have uncheckInHabit method', () {
      expect(HabitApi.uncheckInHabit, isA<Function>());
    });

    test('should have getHabitLogs method', () {
      expect(HabitApi.getHabitLogs, isA<Function>());
    });

    test('should have deleteHabit method', () {
      expect(HabitApi.deleteHabit, isA<Function>());
    });
  });
}
