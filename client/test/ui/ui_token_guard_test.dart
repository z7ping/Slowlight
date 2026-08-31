import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

void main() {
  Iterable<File> businessUiFiles() sync* {
    for (final root in [Directory('lib/screens'), Directory('lib/widgets')]) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.dart')) yield entity;
      }
    }
  }

  test('全局响应式 Token 与 UI 规范保持一致', () {
    expect(SlowlightBreakpoints.tabletMin, 600);
    expect(SlowlightBreakpoints.desktopMin, 900);
    expect(SlowlightBreakpoints.wideMin, 1200);
    expect(SlowlightControlSize.minTouchTarget, 44);
  });

  test('业务 UI 不直接定义裸字号或使用旧 AppTheme.text 尺度', () async {
    final offenders = <String>[];
    final numericFontSize = RegExp(r'fontSize\s*:\s*-?\d+(?:\.\d+)?');
    final legacyTextToken = RegExp(
      r'\bAppTheme\.text(?:Xs|Sm|Md|Lg|Xl|2Xl|3Xl)\b',
    );

    for (final file in businessUiFiles()) {
      final source = await file.readAsString();
      final reasons = <String>[];
      if (numericFontSize.hasMatch(source)) reasons.add('裸数字 fontSize');
      if (legacyTextToken.hasMatch(source)) reasons.add('旧 AppTheme.text*');
      if (reasons.isNotEmpty) {
        offenders.add(
          '${file.path.replaceAll('\\', '/')}: ${reasons.join(', ')}',
        );
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '业务文字必须使用 SlowlightTypography 语义 Token；特殊绘制也只能引用语义字号常量：\n'
          '${offenders.join('\n')}',
    );
  });

  test('业务 UI 不直接定义产品色值', () async {
    final offenders = <String>[];
    final rawColor = RegExp(r'(?<![A-Za-z0-9_])Color\s*\(\s*0x[0-9A-Fa-f]+\s*\)');

    for (final file in businessUiFiles()) {
      final source = await file.readAsString();
      if (rawColor.hasMatch(source)) {
        offenders.add(file.path.replaceAll('\\', '/'));
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '固定产品颜色必须来自主题 / 语义颜色 Token；数据驱动 Color(int.parse(...)) 不受此规则限制：\n'
          '${offenders.join('\n')}',
    );
  });

  test('业务 UI 不使用历史 1024 窗口断点', () async {
    final offenders = <String>[];
    final legacyBreakpoint = RegExp(
      r'(?:MediaQuery\.sizeOf\([^)]*\)\.width|constraints\.maxWidth)\s*(?:>=|>|<=|<)\s*1024(?:\.0)?',
    );

    for (final file in businessUiFiles()) {
      final source = await file.readAsString();
      if (legacyBreakpoint.hasMatch(source)) {
        offenders.add(file.path.replaceAll('\\', '/'));
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          '窗口级设备档位统一使用 SlowlightBreakpoints / ResponsiveLayout；组件内容阈值继续按真实可用宽度判断：\n'
          '${offenders.join('\n')}',
    );
  });

  test('业务 UI 不直接使用 InkResponse 绕过 Fx 交互层', () async {
    final offenders = <String>[];
    final rawInkResponse = RegExp(r'\bInkResponse\s*\(');

    for (final file in businessUiFiles()) {
      final source = await file.readAsString();
      if (rawInkResponse.hasMatch(source)) {
        offenders.add(file.path.replaceAll('\\', '/'));
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason: '产品点击反馈必须通过 FxInkWell / FxButton / FxIconButton 等产品层表达：\n${offenders.join('\n')}',
    );
  });
}
