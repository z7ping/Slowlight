import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/caldav_screen.dart';
import 'package:slowlight/screens/webhook_screen.dart';

void main() {
  test('CalDAV 未知、读取中及刷新失败都不会伪装成 0 个任务', () {
    expect(calDavSyncedTaskLabel(null, loading: false, stale: false),
        '状态未知');
    expect(calDavSyncedTaskLabel(null, loading: true, stale: false),
        '读取中…');
    expect(
      calDavSyncedTaskLabel({'task_count': 4},
          loading: false, stale: true),
      '4 个（上次记录）',
    );
    expect(
      calDavSyncedTaskLabel({'task_count': 0},
          loading: false, stale: false),
      '0 个',
    );
  });

  test('Webhook 批量重试只排除同一地址同一事件的已存在回调', () {
    final records = [
      {'url': 'https://hooks.example/a', 'event': 'task.completed'},
      {'url': 'https://hooks.example/a', 'event': 'habit.checked'},
      {'url': 'https://hooks.example/b', 'event': 'task.created'},
    ];
    expect(
      existingWebhookEvents(records, 'https://hooks.example/a'),
      {'task.completed', 'habit.checked'},
    );
    expect(
      existingWebhookEvents(records, 'https://hooks.example/b'),
      {'task.created'},
    );
  });
}
