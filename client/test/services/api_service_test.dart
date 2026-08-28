import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/api_service.dart';
import 'package:slowlight/services/api/task_api.dart';

void main() {
  group('ApiService task method delegation to TaskApi', () {
    test('should delegate getTasks to TaskApi', () {
      expect(ApiService.getTasks, isA<Function>());
      expect(TaskApi.getTasks, isA<Function>());
    });

    test('should delegate createTask to TaskApi', () {
      expect(ApiService.createTask, isA<Function>());
      expect(TaskApi.createTask, isA<Function>());
    });

    test('should delegate updateTask to TaskApi', () {
      expect(ApiService.updateTask, isA<Function>());
      expect(TaskApi.updateTask, isA<Function>());
    });

    test('should delegate deleteTask to TaskApi', () {
      expect(ApiService.deleteTask, isA<Function>());
      expect(TaskApi.deleteTask, isA<Function>());
    });

    test('should delegate getTodayTasks to TaskApi', () {
      expect(ApiService.getTodayTasks, isA<Function>());
      expect(TaskApi.getTodayTasks, isA<Function>());
    });

    test('should delegate completeTask to TaskApi', () {
      expect(ApiService.completeTask, isA<Function>());
      expect(TaskApi.completeTask, isA<Function>());
    });

    test('should delegate postponeTask to TaskApi', () {
      expect(ApiService.postponeTask, isA<Function>());
      expect(TaskApi.postponeTask, isA<Function>());
    });

    test('should delegate searchTasks to TaskApi', () {
      expect(ApiService.searchTasks, isA<Function>());
      expect(TaskApi.searchTasks, isA<Function>());
    });

    test('should delegate getTasksForMonth to TaskApi', () {
      expect(ApiService.getTasksForMonth, isA<Function>());
      expect(TaskApi.getTasksForMonth, isA<Function>());
    });

    test('should delegate getCompletedTasks to TaskApi', () {
      expect(ApiService.getCompletedTasks, isA<Function>());
      expect(TaskApi.getCompletedTasks, isA<Function>());
    });

    test('should delegate getAllTasks to TaskApi', () {
      expect(ApiService.getAllTasks, isA<Function>());
      expect(TaskApi.getAllTasks, isA<Function>());
    });

    test('should delegate getTask to TaskApi', () {
      expect(ApiService.getTask, isA<Function>());
      expect(TaskApi.getTask, isA<Function>());
    });
  });
}
