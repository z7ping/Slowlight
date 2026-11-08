import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slowlight/services/api/task_api.dart';

void main() {
  test('明确的数据库拒绝可以重试，并隐藏原始 SQL 错误', () {
    final error = TaskCreateException.fromResponse(http.Response(
      '{"code":"task_create_db_error","error":"value too long for type character varying(10)"}',
      500,
    ));
    expect(error.confirmedNotCreated, isTrue);
    expect(error.message, '任务保存失败，请稍后重试');
    expect(error.toString(), isNot(contains('varying')));
  });
  test('未知 HTTP 500/502/503 不允许直接重试创建', () {
    for (final status in [500, 502, 503]) {
      final error = TaskCreateException.fromResponse(http.Response(
        '<html>server error</html>', status,
      ));
      expect(error.confirmedNotCreated, isFalse);
      expect(error.toString(), isNot(contains('<html>')));
    }
  });
  test('明确的请求校验失败可以修改后重试', () {
    final error = TaskCreateException.fromResponse(http.Response(
      '{"error":"invalid task"}', 400,
    ));
    expect(error.confirmedNotCreated, isTrue);
    expect(error.message, contains('任务信息无效'));
  });

  test('X01 任务更新明确拒绝时可修正后重试', () {
    for (final status in [400, 401, 403, 404, 409, 422]) {
      final error = TaskUpdateException.fromResponse(http.Response(
        '{"error":"server raw database response"}', status,
      ));
      expect(error.confirmedNotUpdated, isTrue);
      expect(error.toString(), isNot(contains('database')));
    }
  });

  test('X01 任务更新 500/502/503 不能冒充已知失败直接重试', () {
    for (final status in [500, 502, 503]) {
      final error = TaskUpdateException.fromResponse(http.Response(
        '<html>proxy failure</html>', status,
      ));
      expect(error.confirmedNotUpdated, isFalse);
      expect(error.message, contains('结果未确认'));
      expect(error.toString(), isNot(contains('html')));
    }
  });
}
