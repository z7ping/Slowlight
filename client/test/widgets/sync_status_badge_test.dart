import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/sync_status_badge.dart';

void main() {
  test('SQLite 错误按真实错误代码描述，不把泛用代码冒充确定根因', () {
    const raw =
        'SqliteFfiException(sqlite_error: 1, SqliteException(1): while preparing statement)';
    expect(syncErrorTitle(raw), '本地数据库异常');
    expect(syncErrorDescription(raw), contains('SQLite 返回错误代码 1'));
    expect(syncErrorDescription(raw), isNot(contains('损坏')));
  });

  test('没有具体异常时标记原因待确认，不虚构可复制的错误', () {
    expect(syncErrorTitle(null), '同步处理异常');
    expect(syncErrorDescription(null), contains('原因待确认'));
    expect(syncErrorDescription('  '), contains('原因待确认'));
  });

  test('非 SQLite 失败使用中性描述，保留原始诊断文本展示入口', () {
    const raw = 'SocketException: connection failed';
    expect(syncErrorTitle(raw), '同步处理异常');
    expect(syncErrorDescription(raw), contains('展开技术详情'));
    expect(syncErrorDescription(raw), isNot(contains('SQLite')));
  });

  test('SQLite 未提供错误码时不编造代码', () {
    const raw = 'SqliteException: failed opening cache';
    expect(syncErrorTitle(raw), '本地数据库异常');
    expect(syncErrorDescription(raw), isNot(contains('代码')));
  });
}
