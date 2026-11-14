import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

Widget _host(Widget content, {required bool reduceMotion}) =>
    buildFxTestHost(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Center(child: content),
      ),
    );

Finder _spinnerRotation() => find.descendant(
  of: find.byType(FxSpinner),
  matching: find.byType(RotationTransition),
);

void main() {
  testWidgets('X15 减少动态效果时统一转圈 Loading 静止且仍有状态语义',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(
      const FxSpinner(semanticsLabel: '读取中'),
      reduceMotion: true,
    ));
    expect(find.byType(FxSpinner), findsOneWidget);
    expect(_spinnerRotation(), findsNothing);
    expect(find.bySemanticsLabel('读取中'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await disposeFxTestHost(tester);
  });

  testWidgets('X15 普通模式保留 Spinner 的轻旋转，不改状态和尺寸', (tester) async {
    await tester.pumpWidget(_host(
      const FxSpinner(size: 24), reduceMotion: false,
    ));
    expect(_spinnerRotation(), findsOneWidget);
    final spinner = find.byType(FxSpinner);
    expect(tester.getSize(spinner), const Size(24, 24));
    expect(tester.widget<RotationTransition>(
      _spinnerRotation(),
    ).turns.isAnimating, isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X15 圆形不确定进度在减少动效后不继续调度帧', (tester) async {
    await tester.pumpWidget(_host(
      const FxCircularProgress(), reduceMotion: true,
    ));
    await tester.pump(const Duration(milliseconds: 1250));
    expect(find.byType(FxCircularProgress), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X15 展开组件减少动态效果时立即显示内容和正确图标状态',
      (tester) async {
    var toggles = 0;
    await tester.pumpWidget(_host(
      FxExpansionTile(
        title: const Text('选择分类'),
        onExpansionChanged: (_) => toggles++,
        children: const [Text('详情项目')],
      ),
      reduceMotion: true,
    ));
    final tile = find.byType(FxExpansionTile);
    expect(find.descendant(
      of: tile, matching: find.byType(AnimatedSize),
    ), findsNothing);
    expect(tester.widget<AnimatedRotation>(find.descendant(
      of: tile, matching: find.byType(AnimatedRotation),
    )).duration, Duration.zero);
    expect(tester.widget<AnimatedContainer>(find.descendant(
      of: tile, matching: find.byType(AnimatedContainer),
    )).duration, Duration.zero);
    await tester.tap(find.text('选择分类'));
    await tester.pump();
    expect(find.text('详情项目'), findsOneWidget);
    expect(toggles, 1);
    await tester.tap(find.text('选择分类'));
    await tester.pump();
    expect(toggles, 2);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('切换减少动效时保留展开区里的输入状态', (tester) async {
    final reduced = ValueNotifier<bool>(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(buildFxTestHost(
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: reduced,
        builder: (context, disabled, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disabled),
          child: child!,
        ),
      ),
      home: const Scaffold(
        body: FxExpansionTile(
          title: Text('更多设置'),
          initiallyExpanded: true,
          children: [FxInput(placeholder: '输入备注')],
        ),
      ),
    ));
    final input = find.byType(EditableText);
    await tester.enterText(input, '未保存的备注');
    reduced.value = true;
    await tester.pump();
    expect(tester.widget<EditableText>(input).controller.text, '未保存的备注');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X15 动效设置由开启改为减少时，Spinner/进度立即停止',
      (tester) async {
    final reduced = ValueNotifier<bool>(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(buildFxTestHost(
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: reduced,
        builder: (context, disabled, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disabled,
          ),
          child: child!,
        ),
      ),
      home: const Scaffold(
        body: Column(children: [
          FxSpinner(),
          FxCircularProgress(),
        ]),
      ),
    ));
    expect(_spinnerRotation(), findsOneWidget);
    reduced.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_spinnerRotation(), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
