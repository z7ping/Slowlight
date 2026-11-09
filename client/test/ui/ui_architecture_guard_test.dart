import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('正式 UI 代码不再依赖 Hf / high_fidelity 兼容层', () async {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: '测试需从 client 目录运行');

    final offenders = <String>[];
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      final source = await entity.readAsString();
      final importsLegacyLayer = source.contains('high_fidelity/');
      final usesHfSymbol = RegExp(r'\bHf[A-Z][A-Za-z0-9_]*\b').hasMatch(source);
      if (importsLegacyLayer || usesHfSymbol) offenders.add(normalized);
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '请迁移到 Fx* 或 Feature Widget，禁止继续依赖 Hf 兼容层：\n'
          '${offenders.join('\n')}',
    );
  });

  test('正式 UI 不新增阶段性版本命名', () async {
    final lib = Directory('lib');
    final offenders = <String>[];
    final stageFileName = RegExp(
      r'(^|/)(?:new|old|final|high_fidelity)(?:_|/)|_(?:v2|v3)(?:\.|_|/)',
      caseSensitive: false,
    );
    final stageClassName = RegExp(
      r'\bclass\s+(?:[A-Za-z0-9_]*(?:V2|V3)|(?:New|Old|Final)[A-Z][A-Za-z0-9_]*)\b',
    );

    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      final source = await entity.readAsString();
      if (stageFileName.hasMatch(normalized) || stageClassName.hasMatch(source)) {
        offenders.add(normalized);
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '正式 UI 禁止使用 new/old/final/high_fidelity/V2/V3 等阶段性实现命名：\n'
          '${offenders.join('\n')}',
    );
  });

  test('Screen / 业务 Widget 不直接依赖 shadcn_ui 视觉组件', () async {
    final roots = [Directory('lib/screens'), Directory('lib/widgets')];
    final offenders = <String>[];

    for (final root in roots) {
      if (!root.existsSync()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = await entity.readAsString();
        if (source.contains("package:shadcn_ui/shadcn_ui.dart")) {
          offenders.add(entity.path.replaceAll('\\', '/'));
        }
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '业务层应通过 Fx* / Feature Widget 使用视觉能力；shadcn_ui 由 Fx 作为主要视觉底座统一封装：\n'
          '${offenders.join('\n')}',
    );
  });

  test('Screen / 业务 Widget 不绕过 Fx 使用已有 Material 视觉控件', () async {
    final roots = [Directory('lib/screens'), Directory('lib/widgets')];
    final forbidden = <String, RegExp>{
      'TextButton': RegExp(r'\bTextButton(?:\.[A-Za-z]+)?\s*\('),
      'ElevatedButton': RegExp(r'\bElevatedButton(?:\.[A-Za-z]+)?\s*\('),
      'OutlinedButton': RegExp(r'\bOutlinedButton(?:\.[A-Za-z]+)?\s*\('),
      'FilledButton': RegExp(r'\bFilledButton(?:\.[A-Za-z]+)?\s*\('),
      'IconButton': RegExp(r'\bIconButton(?:\.[A-Za-z]+)?\s*\('),
      'TextField': RegExp(r'\bTextField\s*\('),
      'DropdownButton': RegExp(r'\bDropdownButton(?:<[^>]+>)?\s*\('),
      'DropdownButtonFormField': RegExp(
        r'\bDropdownButtonFormField(?:<[^>]+>)?\s*\(',
      ),
      'DropdownMenu': RegExp(r'\bDropdownMenu(?:<[^>]+>)?\s*\('),
      'ChoiceChip': RegExp(r'\bChoiceChip\s*\('),
      'FilterChip': RegExp(r'\bFilterChip\s*\('),
      'ActionChip': RegExp(r'\bActionChip\s*\('),
      'InputChip': RegExp(r'\bInputChip\s*\('),
      'SwitchListTile': RegExp(r'\bSwitchListTile(?:\.adaptive)?\s*\('),
      'Slider': RegExp(r'\bSlider\s*\('),
      'Checkbox': RegExp(r'\bCheckbox\s*\('),
      'Switch': RegExp(r'\bSwitch\s*\('),
      'Radio': RegExp(r'\bRadio(?:<[^>]+>)?\s*\('),
      'RadioListTile': RegExp(r'\bRadioListTile(?:<[^>]+>)?\s*\('),
      'LinearProgressIndicator': RegExp(r'\bLinearProgressIndicator\s*\('),
      'CircularProgressIndicator': RegExp(
        r'\bCircularProgressIndicator\s*\(',
      ),
      'Divider': RegExp(r'\bDivider\s*\('),
      'VerticalDivider': RegExp(r'\bVerticalDivider\s*\('),
      'InkWell': RegExp(r'\bInkWell\s*\('),
      'Tooltip': RegExp(r'\bTooltip\s*\('),
      'Card': RegExp(r'(?<![A-Za-z0-9_])Card\s*\('),
      'SnackBar': RegExp(r'\bSnackBar\s*\('),
      'SnackBarAction': RegExp(r'\bSnackBarAction\s*\('),
      'ScaffoldMessenger.of': RegExp(r'\bScaffoldMessenger\.of\s*\('),
      'showModalBottomSheet': RegExp(
        r'\bshowModalBottomSheet(?:<[^>]+>)?\s*\(',
      ),
      'BottomSheet': RegExp(r'(?<![A-Za-z0-9_])BottomSheet\s*\('),
      'showBottomSheet': RegExp(r'\bshowBottomSheet(?:<[^>]+>)?\s*\('),
      'PopupMenuButton': RegExp(r'\bPopupMenuButton(?:<[^>]+>)?\s*\('),
      'PopupMenuItem': RegExp(r'\bPopupMenuItem(?:<[^>]+>)?\s*\('),
      'CheckedPopupMenuItem': RegExp(
        r'\bCheckedPopupMenuItem(?:<[^>]+>)?\s*\(',
      ),
      'PopupMenuDivider': RegExp(r'\bPopupMenuDivider\s*\('),
      'showMenu': RegExp(r'\bshowMenu(?:<[^>]+>)?\s*\('),
      'MenuAnchor': RegExp(r'\bMenuAnchor\s*\('),
      'MenuItemButton': RegExp(r'\bMenuItemButton\s*\('),
      'showDialog': RegExp(r'\bshowDialog(?:<[^>]+>)?\s*\('),
      'AlertDialog': RegExp(r'\bAlertDialog\s*\('),
      'SimpleDialog': RegExp(r'\bSimpleDialog\s*\('),
      'SimpleDialogOption': RegExp(r'\bSimpleDialogOption\s*\('),
      'Dialog': RegExp(r'(?<![A-Za-z0-9_])Dialog\s*\('),
      'showDatePicker': RegExp(r'\bshowDatePicker\s*\('),
      'showTimePicker': RegExp(r'\bshowTimePicker\s*\('),
      'ListTile': RegExp(r'(?<![A-Za-z0-9_])ListTile\s*\('),
      'ExpansionTile': RegExp(r'\bExpansionTile\s*\('),
    };
    final offenders = <String>[];

    for (final root in roots) {
      if (!root.existsSync()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll('\\', '/');
        final source = await entity.readAsString();
        final hits = forbidden.entries
            .where((entry) => entry.value.hasMatch(source))
            .map((entry) => entry.key)
            .toList(growable: false);
        if (hits.isNotEmpty) offenders.add('$normalized: ${hits.join(', ')}');
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          'Screen / 业务 Widget 必须通过 Fx* 使用产品视觉控件。Fx 适配层可以 Shad 优先，并在有明确平台能力原因时封装 Material：\n'
          '${offenders.join('\n')}',
    );
  });

  test('业务操作栏不使用 WrapAlignment.spaceBetween 猜测左右位置', () async {
    final roots = [Directory('lib/screens'), Directory('lib/widgets')];
    final offenders = <String>[];

    for (final root in roots) {
      if (!root.existsSync()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll('\\', '/');
        final source = await entity.readAsString();
        if (source.contains('WrapAlignment.spaceBetween')) {
          offenders.add(normalized);
        }
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '页面/区块操作区必须使用 FxActionBar / FxDialogActions 或明确 Row 锚点；'
          '禁止用 WrapAlignment.spaceBetween 让按钮在换行后随机落位：\n'
          '${offenders.join('\n')}',
    );
  });

  test('Fx 弹窗内容不重复自绘关闭按钮', () async {
    final roots = [Directory('lib/screens'), Directory('lib/widgets')];
    final offenders = <String>[];
    final closeTooltip = RegExp(r'''tooltip\s*:\s*['"]关闭['"]''');

    for (final root in roots) {
      if (!root.existsSync()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll('\\', '/');
        final source = await entity.readAsString();
        final ownsDialogChrome =
            source.contains('FxDialogSurface(') || source.contains('FxDialog.show');
        if (ownsDialogChrome && closeTooltip.hasMatch(source)) {
          offenders.add(normalized);
        }
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          'FxDialog / FxDialogSurface 已负责弹窗关闭入口，内容区不得再次自绘“关闭”按钮：\n'
          '${offenders.join('\n')}',
    );
  });

  test('RefreshIndicator 只允许存在于 FxRefresh 适配层', () async {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: '测试需从 client 目录运行');

    const adapter = 'lib/ui/widgets/fx_refresh.dart';
    final rawRefresh = RegExp(r'\bRefreshIndicator\s*\(');
    final offenders = <String>[];

    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized == adapter) continue;
      final source = await entity.readAsString();
      if (rawRefresh.hasMatch(source)) offenders.add(normalized);
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          'shadcn_ui 暂无 pull-to-refresh；Material RefreshIndicator 只能封装在 FxRefresh 适配层，业务代码不得直接使用：\n'
          '${offenders.join('\n')}',
    );
  });

  test('通用动作布局不再使用固定宽度直接判定换行', () async {
    const shared = [
      'lib/ui/widgets/fx_action_layout.dart',
      'lib/ui/widgets/fx_page_header.dart',
      'lib/ui/widgets/fx_section_header.dart',
    ];
    final offenders = <String>[];
    final forcedWidth = RegExp(
      r'constraints\.maxWidth\s*<\s*(?:[0-9]+(?:\.[0-9]+)?|stackBelow)\b',
    );
    for (final path in shared) {
      final source = await File(path).readAsString();
      if (forcedWidth.hasMatch(source)) offenders.add(path);
    }
    final settings = await File('lib/screens/settings_screen.dart').readAsString();
    final begin = settings.indexOf('Widget _settingLine(');
    final end = settings.indexOf('Widget _label(', begin);
    expect(begin, greaterThanOrEqualTo(0));
    expect(end, greaterThan(begin));
    final settingLine = settings.substring(begin, end);
    if (RegExp(r'constraints\.maxWidth\s*<\s*(?:360|520)\b')
        .hasMatch(settingLine)) {
      offenders.add('lib/screens/settings_screen.dart:_settingLine');
    }
    expect(
      offenders,
      isEmpty,
      reason: '通用动作区须根据内容实际占用换行；'
          '禁止再引入 300/360/520dp 等固定阈值。',
    );
  });

  test('高频底部操作不按字号和整屏宽度强制换行', () async {
    const guards = <String, List<String>>{
      'lib/widgets/dashboard/dashboard_body.dart': [
        'constraints.maxWidth < 300 * scale',
      ],
      'lib/widgets/sync_status_badge.dart': [
        'constraints.maxWidth < 360',
      ],
      'lib/widgets/habit_checkin_dialog.dart': [
        'stackMobileActions',
      ],
      'lib/widgets/habit_editor_dialog.dart': [
        'stackMobileActions',
      ],
    };
    final offenders = <String>[];
    for (final entry in guards.entries) {
      final source = await File(entry.key).readAsString();
      for (final pattern in entry.value) {
        if (source.contains(pattern)) offenders.add('${entry.key}: $pattern');
      }
    }
    expect(offenders, isEmpty, reason: '高频操作按内容适配并保留 5:7 比例，不能仅凭字号强制竖排');
  });
}
