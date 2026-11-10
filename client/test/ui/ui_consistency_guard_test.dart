import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('已收口功能区域不得重新混入 Material 功能图标', () async {
    const files = [
      'lib/screens/settings_screen.dart',
      'lib/screens/focus_home_screen.dart',
      'lib/screens/login_screen.dart',
      'lib/screens/about_screen.dart',
      'lib/screens/task_tool_screen.dart',
      'lib/screens/habit_tool_screen.dart',
      'lib/screens/today_review_screen.dart',
      'lib/screens/search_screen.dart',
      'lib/screens/pomodoro_screen.dart',
      'lib/ui/widgets/fx_menu.dart',
      'lib/screens/feishu_screen_sections.dart',
      'lib/screens/caldav_screen.dart',
      'lib/screens/webhook_screen.dart',
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

  test('正式导航和登录图标与唯一高保真原型保持一致', () async {
    final home = await File('lib/screens/focus_home_screen.dart').readAsString();
    final login = await File('lib/screens/login_screen.dart').readAsString();
    final tasks = await File('lib/screens/task_tool_screen.dart').readAsString();
    final menu = await File('lib/ui/widgets/fx_menu.dart').readAsString();
    final pubspec = await File('pubspec.yaml').readAsString();

    // 底栏与工具抽屉使用同一个 Lucide Repeat，不画两套习惯图标。
    expect(RegExp(r'LucideIcons\.repeat\b').allMatches(home).length, 2);
    expect(home.contains('LucideIcons.repeat2'), isFalse);
    // GitHub 是品牌资产，不能拿 gitFork 伪装成 GitHub 猫头。
    expect(login.contains("key: const ValueKey('login.github_brand_hero')"), isTrue);
    expect(login.contains('assets/github_mark.png'), isTrue);
    expect(pubspec.contains('- assets/github_mark.png'), isTrue);
    expect(login.contains('LucideIcons.gitFork'), isFalse);
    expect(tasks.contains('LucideIcons.check,'), isTrue);
    expect(menu.contains('Icon(LucideIcons.ellipsis'), isTrue);
  });

  test('正式界面不得用 Emoji 冒充周期、数据状态和弹窗功能图标', () async {
    final habit = await File('lib/screens/habit_tool_screen.dart').readAsString();
    final review = await File('lib/screens/today_review_screen.dart').readAsString();
    final search = await File('lib/screens/search_screen.dart').readAsString();
    final focus = await File('lib/screens/pomodoro_screen.dart').readAsString();
    for (final source in [habit, review]) {
      expect(source.contains("'morning' => '早晨'"), isTrue);
      expect(source.contains("'night' => '晚间'"), isTrue);
      expect(source.contains("'morning' => '☀️"), isFalse);
      expect(source.contains("'night' => '🌙"), isFalse);
    }
    // 自定义习惯/清单 Emoji 是数据，不在此处禁用。
    expect(search.contains('🔥 \${habit.streakCount}'), isFalse);
    expect(focus.contains("title: '🍅 专注设置'"), isFalse);
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
