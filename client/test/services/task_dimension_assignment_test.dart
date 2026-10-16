import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/observation_tag.dart';
import 'package:slowlight/repositories/observation_tag_repository.dart';
import 'package:slowlight/services/task_dimension_assignment.dart';

class _FakeObservationTags extends ObservationTagRepository {
  final List<ObservationTag> items = [];
  int createCalls = 0;

  @override
  Future<List<ObservationTag>> getAll() async => List.of(items);

  @override
  Future<ObservationTag> create({
    required String name,
    required String icon,
    required String color,
    String? dimensionKey,
  }) async {
    createCalls++;
    final tag = ObservationTag(
      id: items.length + 10,
      name: name,
      icon: icon,
      color: color,
      dimensionKey: dimensionKey,
    );
    items.add(tag);
    return tag;
  }
}

void main() {
  group('TaskDimensionAssignment', () {
    test('未更改维度时保留调用入口原有观察标签', () async {
      final repo = _FakeObservationTags();
      final assignment = TaskDimensionAssignment(repository: repo);
      expect(await assignment.resolve(
        dimensionKey: null,
        originalTagId: 88,
        changed: false,
      ), 88);
      expect(repo.createCalls, 0);
    });

    test('主动选择未归类会清除既有标签', () async {
      final repo = _FakeObservationTags();
      final assignment = TaskDimensionAssignment(repository: repo);
      expect(await assignment.resolve(
        dimensionKey: null,
        originalTagId: 88,
      ), isNull);
      expect(repo.createCalls, 0);
    });

    test('优先复用现有的对应维度默认观察标签', () async {
      final repo = _FakeObservationTags();
      repo.items.add(const ObservationTag(
        id: 4,
        name: '身体',
        icon: '💪',
        color: '#52c41a',
        dimensionKey: 'body',
        isDefault: true,
      ));
      final assignment = TaskDimensionAssignment(repository: repo);
      expect(await assignment.dimensionOf(4), 'body');
      expect(await assignment.resolve(dimensionKey: 'body'), 4);
      expect(repo.createCalls, 0);
    });

    test('没有通用标签时按需创建，再次选择时复用', () async {
      final repo = _FakeObservationTags();
      final assignment = TaskDimensionAssignment(repository: repo);
      final first = await assignment.resolve(dimensionKey: 'cognition');
      final second = await assignment.resolve(dimensionKey: 'cognition');
      expect(first, second);
      expect(repo.createCalls, 1);
      expect(repo.items.single.dimensionKey, 'cognition');
      expect(repo.items.single.name, '认知');
    });

    test('不能将同维度的自定义观察标签当成通用维度标签', () async {
      final repo = _FakeObservationTags();
      repo.items.add(const ObservationTag(
        id: 2,
        name: '分心',
        icon: '🏷️',
        color: '#1890ff',
        dimensionKey: 'cognition',
      ));
      final assignment = TaskDimensionAssignment(repository: repo);
      final id = await assignment.resolve(dimensionKey: 'cognition');
      expect(id, isNot(2));
      expect(repo.items.last.name, '认知');
    });
  });
}
