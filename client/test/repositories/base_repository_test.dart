import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/repositories/base_repository.dart';

/// Concrete implementation used to test the abstract contract
class _TestRepository extends BaseRepository<String> {
  @override
  Future<List<String>> getAll() async => [];

  @override
  Future<String?> getById(int id) async => null;

  @override
  Future<String> create(String item) async => item;

  @override
  Future<String> update(String item) async => item;

  @override
  Future<void> delete(int id) async {}
}

void main() {
  group('BaseRepository', () {
    test('should be abstract class with required CRUD methods', () {
      // Verify the abstract contract exists and can be implemented
      final repo = _TestRepository();
      expect(repo, isA<BaseRepository<String>>());
    });

    test('getAll returns list', () async {
      final repo = _TestRepository();
      final result = await repo.getAll();
      expect(result, isA<List<String>>());
      expect(result, isEmpty);
    });

    test('getById returns null for missing item', () async {
      final repo = _TestRepository();
      final result = await repo.getById(1);
      expect(result, isNull);
    });

    test('create returns the item', () async {
      final repo = _TestRepository();
      final result = await repo.create('test');
      expect(result, equals('test'));
    });

    test('update returns the item', () async {
      final repo = _TestRepository();
      final result = await repo.update('updated');
      expect(result, equals('updated'));
    });

    test('delete completes without error', () async {
      final repo = _TestRepository();
      await repo.delete(1);
    });
  });
}
