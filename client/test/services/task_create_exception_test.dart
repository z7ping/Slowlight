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
}
