import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> inspectWidgetTests(Directory directory) async {
    final offenders = <String>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.endsWith('/test_ui_architecture_guard_test.dart')) continue;

      final source = await entity.readAsString();
      if (!source.contains('testWidgets(')) continue;

      final reasons = <String>[];
      if (!source.contains("../support/fx_test_host.dart")) {
        reasons.add('未使用 buildFxTestHost');
      }
      if (source.contains('package:shadcn_ui/shadcn_ui.dart')) {
        reasons.add('直接依赖 shadcn_ui');
      }
      if (source.contains('ShadTheme(') || source.contains('MaterialApp(')) {
        reasons.add('自行创建视觉根节点');
      }
      final legacyVisual = RegExp(
        r'\b(?:ElevatedButton|TextButton|OutlinedButton|FilledButton|IconButton|Tooltip|SnackBar)\s*\(',
      );
      if (legacyVisual.hasMatch(source) ||
          source.contains('ScaffoldMessenger.of(')) {
        reasons.add('直接使用旧 Material 视觉控件');
      }

      if (reasons.isNotEmpty) {
        offenders.add('$normalized: ${reasons.join(', ')}');
      }
    }
    offenders.sort();
    return offenders;
  }

  test('Screen Widget Test 统一通过 Fx 测试宿主验证产品 UI', () async {
    final screens = Directory('test/screens');
    expect(screens.existsSync(), isTrue, reason: '测试需从 client 目录运行');

    final offenders = await inspectWidgetTests(screens);
    expect(
      offenders,
      isEmpty,
      reason:
          'Screen Widget Test 必须像正式页面一样从 Fx 产品层进入，避免测试继续锁定旧 Material/shadcn 实现细节：\n'
          '${offenders.join('\n')}',
    );
  });

  test('Fx Widget Test 统一使用产品测试宿主，不自建平行视觉环境', () async {
    final ui = Directory('test/ui');
    expect(ui.existsSync(), isTrue, reason: '测试需从 client 目录运行');

    final offenders = await inspectWidgetTests(ui);
    expect(
      offenders,
      isEmpty,
      reason:
          'Fx Widget Test 应复用统一测试宿主，避免测试主题与正式应用视觉上下文漂移：\n'
          '${offenders.join('\n')}',
    );
  });
}
