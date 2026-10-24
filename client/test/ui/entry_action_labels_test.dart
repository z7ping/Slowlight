import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('任务与观察保留独立入口并使用统一命名', () {
    final dashboard = File('lib/widgets/dashboard/dashboard_body.dart')
        .readAsStringSync();
    final task = File('lib/screens/task_create_sheet.dart')
        .readAsStringSync();
    final observation = File('lib/widgets/reflection_composer.dart')
        .readAsStringSync();
    final review = File('lib/screens/today_review_screen.dart')
        .readAsStringSync();
    final stats = File('lib/screens/stats_screen.dart').readAsStringSync();
    final mobile = File('lib/screens/focus_home_screen.dart')
        .readAsStringSync();

    expect(dashboard, contains("label: '添加任务'"));
    expect(dashboard, contains("label: '记录观察'"));
    expect(task, contains("title: '添加任务'"));
    // 保存中与部分成功恢复可以使用各自文案，入口的任务/观察语义保持独立。
    expect(task, contains(RegExp(r"label:\s*[^\n]*'添加任务'")));
    expect(observation, contains("title: '记录观察'"));
    expect(review, contains("title: '记录观察'"));
    expect(mobile, contains("tooltip: '记录观察'"));
    expect(stats, contains("label: '记录观察'"));

    for (final source in [dashboard, task, observation, review, mobile, stats]) {
      expect(source, isNot(contains('记录任务')));
      expect(source, isNot(contains('写下观察')));
    }
  });
}
