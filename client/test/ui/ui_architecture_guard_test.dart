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

  test('Screen 不直接依赖 shadcn_ui 视觉组件', () async {
    final screens = Directory('lib/screens');
    if (!screens.existsSync()) return;

    final offenders = <String>[];
    await for (final entity in screens.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = await entity.readAsString();
      if (source.contains("package:shadcn_ui/shadcn_ui.dart")) {
        offenders.add(entity.path.replaceAll('\\', '/'));
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '业务 Screen 应通过 Fx* / Feature Widget 使用视觉能力，不直接依赖 shadcn_ui：\n'
          '${offenders.join('\n')}',
    );
  });

  test('整个 lib 不直接使用已有 Fx 替代的 Material 视觉控件', () async {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: '测试需从 client 目录运行');

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

    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      final source = await entity.readAsString();
      final hits = forbidden.entries
          .where((entry) => entry.value.hasMatch(source))
          .map((entry) => entry.key)
          .toList(growable: false);
      if (hits.isNotEmpty) offenders.add('$normalized: ${hits.join(', ')}');
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '整个 lib 的产品视觉控件必须通过 Fx* / shadcn 封装使用；Material 仅保留布局、导航、滚动、动画、焦点、页面骨架等非视觉基础设施：\n'
          '${offenders.join('\n')}',
    );
  });

  test('业务操作栏不使用 WrapAlignment.spaceBetween 猜测左右位置', () async {
    final roots = [Directory('lib/screens'), Directory('lib/widgets')];
    final offenders = <String>[];

    // 编辑型任务 Footer 是显式语义例外：删除在左、保存修改在右。
    // 后续迁移为 FxDialogActions 后可删除此白名单。
    const allowed = {'lib/widgets/task_detail_sheet.dart'};

    for (final root in roots) {
      if (!root.existsSync()) continue;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll('\\', '/');
        if (allowed.contains(normalized)) continue;
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
          'shadcn_ui 0.26.5 暂无 pull-to-refresh；Material RefreshIndicator 只能封装在 FxRefresh 适配层，业务代码不得直接使用：\n'
          '${offenders.join('\n')}',
    );
  });
}
