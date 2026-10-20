import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('已收口功能区域不得重新混入 Material 功能图标', () async {
    const files = [
      'lib/screens/settings_screen.dart',
      'lib/screens/feishu_screen_sections.dart',
      'lib/screens/caldav_screen.dart',
      'lib/screens/webhook_screen.dart',
      'lib/screens/inbox_screen.dart',
      'lib/screens/integration_screen.dart',
      'lib/widgets/task_tile.dart',
      'lib/widgets/task_filter_sort_sheet.dart',
    ];
    final mixed = <String>[];
    final materialIcon = RegExp(r'(?<![A-Za-z0-9_])Icons\.');
    for (final path in files) {
      final source = await File(path).readAsString();
      if (materialIcon.hasMatch(source)) mixed.add(path);
    }
    expect(
      mixed,
      isEmpty,
      reason: '功能图标必须沿用现有 Lucide 语义体系，避免同模块并行：${mixed.join(', ')}',
    );
  });

  test('所有标签入口由 TagChoiceField 唯一承载 FxChoiceChip 选择视觉', () async {
    final shared = await File('lib/widgets/tag_choice_field.dart').readAsString();
    expect(shared.contains('FxChoiceChip('), isTrue);
    for (final path in [
      'lib/widgets/tag_picker.dart',
      'lib/widgets/system_tag_picker.dart',
    ]) {
      final source = await File(path).readAsString();
      expect(source.contains('TagChoiceField('), isTrue, reason: path);
      expect(source.contains('FxChoiceChip('), isFalse,
          reason: '$path 不应重新自绘第二套标签 Chip');
    }
  });

  test('业务层不得重新引用待退役的特殊间距别名', () async {
    final oldSpacing = RegExp(
      r'\bSlowlightSpacing\.(?:xxs|sm|lg|xxl|section|spacious)\b',
    );
    final offenders = <String>[];
    for (final directory in ['lib/screens', 'lib/widgets']) {
      await for (final entity in Directory(directory).list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = await entity.readAsString();
        if (oldSpacing.hasMatch(source)) offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '旧尺度只允许 Fx 兼容层保留，不得继续扩散至业务页面',
    );
  });
}
