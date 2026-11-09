import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/webhook_screen.dart';

void main() {
  test('Webhook URL 必须是 HTTP(S)，支持自托管内网服务器', () {
    expect(validateWebhookUrl(''), isNotNull);
    expect(validateWebhookUrl('ftp://example.org/callback'), isNotNull);
    expect(validateWebhookUrl('not a url'), isNotNull);
    expect(validateWebhookUrl('https://example.org/hook'), isNull);
    expect(validateWebhookUrl('http://127.0.0.1:5678/webhook'), isNull);
    expect(validateWebhookUrl('http://localhost:5678/webhook'), isNull);
  });

  test('批量回调按照地址与事件去重，不跨地址误判', () {
    final records = [
      {'url': 'https://example.org/hook', 'event': 'task.completed'},
      {'url': 'https://example.org/hook', 'event': 'habit.checked'},
    ];
    expect(existingWebhookEvents(records, 'https://example.org/hook'),
        containsAll(['task.completed', 'habit.checked']));
    expect(existingWebhookEvents(records, 'https://other.example.org/hook'),
        isEmpty);
  });

  test('Webhook 正式事件列表保留六个已发布键', () {
    expect(webhookEvents.map((event) => event.key).toSet(), {
      'task.completed', 'task.created', 'task.updated', 'task.deleted',
      'habit.checked', 'session.ended',
    });
  });
}
