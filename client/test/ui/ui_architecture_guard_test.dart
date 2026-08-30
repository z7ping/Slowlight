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
      if (normalized.contains('/widgets/high_fidelity/')) continue;

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
}
