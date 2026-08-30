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
      if (importsLegacyLayer || usesHfSymbol) {
        offenders.add(normalized);
      }
    }

    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason: '请迁移到 Fx* 或 Feature Widget，禁止继续依赖 Hf 兼容层：\n'
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
      reason: '正式 UI 禁止使用 new/old/final/high_fidelity/V2/V3 等阶段性实现命名：\n'
          '${offenders.join('\n')}',
    );
  });

  test('Screen 不直接依赖 shadcn_ui 视觉组件', () async {
    final screens = Directory('lib/screens');
    if (!screens.existsSync()) return;

    final offenders = <String>[];
    await for (final entity in screens.list(recursive: true, followLinks: false)) {
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
      reason: '业务 Screen 应通过 Fx* / Feature Widget 使用视觉能力，不直接依赖 shadcn_ui：\n'
          '${offenders.join('\n')}',
    );
  });
}
