import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/api/task_api.dart';

void main() {
  group('TaskApi', () {
    test('should have getTasks method', () {
      expect(TaskApi.getTasks, isA<Function>());
    });

    test('should have createTask method', () {
      expect(TaskApi.createTask, isA<Function>());
    });

    test('should have getTodayTasks method', () {
      expect(TaskApi.getTodayTasks, isA<Function>());
    });
  });
}
