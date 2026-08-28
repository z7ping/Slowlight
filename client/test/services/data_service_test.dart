import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/data_service.dart';
import 'package:slowlight/repositories/task_repository.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/repositories/list_repository.dart';
import 'package:slowlight/repositories/tag_repository.dart';

void main() {
  group('DataService', () {
    late DataService service;

    setUp(() {
      service = DataService();
    });

    test('should be a singleton', () {
      final a = DataService();
      final b = DataService();
      expect(identical(a, b), isTrue);
    });

    test('should expose taskRepository', () {
      expect(service.taskRepository, isA<TaskRepository>());
    });

    test('should expose habitRepository', () {
      expect(service.habitRepository, isA<HabitRepository>());
    });

    test('should expose listRepository', () {
      expect(service.listRepository, isA<ListRepository>());
    });

    test('should expose tagRepository', () {
      expect(service.tagRepository, isA<TagRepository>());
    });

    test('should have getTasksByListId method', () {
      expect(service.getTasksByListId, isA<Function>());
    });

    test('should have getTodayTasks method', () {
      expect(service.getTodayTasks, isA<Function>());
    });

    test('should have getHabits method', () {
      expect(service.getHabits, isA<Function>());
    });

    test('should have getLists method', () {
      expect(service.getLists, isA<Function>());
    });

    test('should have getTags method', () {
      expect(service.getTags, isA<Function>());
    });
  });
}
