import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('旧首页、侧栏与维度字段不得悄悄重返正式业务调用链', () async {
    const compatibilityFiles = {
      'lib/screens/home_drawer.dart': 'HomeDrawer',
      'lib/screens/home_today_body.dart': 'HomeTodayBody',
      'lib/widgets/task_dimension_field.dart': 'TaskDimensionField',
    };
    final usage = <String>[];
    await for (final entry in Directory('lib').list(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      final name = entry.path.replaceAll('\\', '/');
      if (compatibilityFiles.containsKey(name)) continue;
      final source = await entry.readAsString();
      for (final symbol in compatibilityFiles.values) {
        if (RegExp('\\b$symbol\\b').hasMatch(source)) {
          usage.add('$name: $symbol');
        }
      }
    }
    expect(
      usage,
      isEmpty,
      reason: '非活动兼容文件仅保留历史兼容，不得以第二套正式 UI 重新引入',
    );
  });

  test('任务工具页仍使用活动的桌面详情面板，不误删现役实现', () async {
    final source = await File('lib/screens/task_tool_screen.dart').readAsString();
    expect(source.contains("import 'home_task_detail_panel.dart';"), isTrue);
    expect(source.contains('HomeTaskDetailPanel('), isTrue);
  });
}
