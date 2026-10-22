import 'package:flutter/material.dart' show Scrollable, ScrollableState, Size, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/diagnostics_screen.dart';
import 'package:slowlight/services/app_error_logger.dart';

import '../support/fx_test_host.dart';

class _TestLogger extends AppErrorLogger {
  _TestLogger(this.text, {this.readFails = false});

  String text;
  bool readFails;
  int reads = 0;

  @override
  Future<String> readRecent({int maxCharacters = 24000}) async {
    reads++;
    if (readFails) throw StateError('日志读取异常');
    return text;
  }

  @override
  Future<String> readText() async => text;

  @override
  Future<void> clear() async {
    text = '';
  }
}

void main() {
  testWidgets('无日志：显示紧凑空状态，不能导出或清空', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: DiagnosticsScreen(logger: _TestLogger('')),
    ));
    await tester.pump();
    expect(find.text('暂无错误记录'), findsOneWidget);
    expect(find.text('清空本机日志'), findsNothing);
    expect(find.text('当前没有可导出的记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('有日志：默认折叠、展开可选择原文', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: DiagnosticsScreen(logger: _TestLogger('2026-10-21 exception: test')),
    ));
    await tester.pump();
    expect(find.text('已有错误记录'), findsOneWidget);
    expect(find.text('清空本机日志'), findsOneWidget);
    expect(find.text('2026-10-21 exception: test'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('diagnostics.raw_toggle')));
    await tester.pump();
    expect(find.text('2026-10-21 exception: test'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('有记录时清空需要危险确认，取消不删除', (tester) async {
    final logger = _TestLogger('保留的本机日志');
    await tester.pumpWidget(buildFxTestHost(
      home: DiagnosticsScreen(logger: logger),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diagnostics.clear')));
    await tester.pump();
    expect(find.text('清空错误日志'), findsOneWidget);
    expect(logger.text, '保留的本机日志');
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(logger.text, '保留的本机日志');
    await disposeFxTestHost(tester);
  });

  testWidgets('日志读取失败和重新读取不能冒充无错误', (tester) async {
    final logger = _TestLogger('', readFails: true);
    await tester.pumpWidget(buildFxTestHost(
      home: DiagnosticsScreen(logger: logger),
    ));
    await tester.pump();
    expect(find.text('无法读取错误记录'), findsOneWidget);
    expect(find.text('暂无错误记录'), findsNothing);
    logger.readFails = false;
    await tester.tap(find.byKey(const ValueKey('diagnostics.retry')));
    await tester.pump();
    expect(find.text('暂无错误记录'), findsOneWidget);
    expect(logger.reads, 2);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 日志原文固定高度，展开后默认定位最新记录', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final content = List.generate(100, (i) => '2026-10-22 09:${i.toString().padLeft(2, '0')} error $i').join('\n');
    await tester.pumpWidget(buildFxTestHost(
      home: DiagnosticsScreen(logger: _TestLogger(content)),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diagnostics.raw_toggle')));
    await tester.pumpAndSettle();
    final viewport = find.byKey(const ValueKey('diagnostics.raw_viewport'));
    expect(viewport, findsOneWidget);
    expect(tester.getSize(viewport).height, 280);
    final scrollable = find.descendant(
      of: viewport,
      matching: find.byType(Scrollable),
    );
    final scroller = tester.state<ScrollableState>(scrollable);
    expect(scroller.position.maxScrollExtent, greaterThan(0));
    expect(scroller.position.pixels,
        closeTo(scroller.position.maxScrollExtent, 1));
    await disposeFxTestHost(tester);
  });

}
