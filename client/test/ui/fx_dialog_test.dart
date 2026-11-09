import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  Widget buildHost() {
    return buildFxTestHost(
      home: Builder(
        builder: (context) => Scaffold(
          body: FxButton(
            label: '打开弹窗',
            onPressed: () => FxDialog.confirm(
              context: context,
              title: '删除任务',
              content: '确定删除吗？',
              confirmText: '删除',
              destructive: true,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Windows FxDialog 保留 Shad 弹窗文字默认值并允许点击外部取消', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(buildHost());
    final barrierBaseline = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();

    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline + 1));
    expect(
      barriers.any((barrier) => barrier.color == FxDialog.barrierColor),
      isTrue,
    );

    expect(tester.widget<Text>(find.text('删除任务')).style, isNull);
    expect(tester.widget<Text>(find.text('确定删除吗？')).style, isNull);
    expect(tester.widget<Text>(find.text('取消')).style, isNull);
    expect(tester.widget<Text>(find.text('删除')).style, isNull);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('删除任务'), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline));
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 草稿确认采用左 40% 放弃、右 60% 继续编辑', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? discarded;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(builder: (context) => FxButton(
          label: '编辑草稿',
          onPressed: () async {
            discarded = await FxDialog.confirm(
              context: context,
              title: '放弃未保存的修改？',
              content: '退出后草稿不会保存。',
              confirmText: '放弃修改',
              destructive: true,
              draftDiscard: true,
            );
          },
        )),
      ),
    ));

    await tester.tap(find.text('编辑草稿'));
    await tester.pumpAndSettle();

    final discard = find.byKey(const ValueKey('fx.dialog.discardDraft'));
    final keep = find.byKey(const ValueKey('fx.dialog.keepEditing'));
    expect(find.byKey(const ValueKey('fx.dialog.draftActions')), findsOneWidget);
    expect(discard, findsOneWidget);
    expect(keep, findsOneWidget);
    expect(tester.widget<FxButton>(discard).variant, FxButtonVariant.outline);
    expect(tester.widget<FxButton>(keep).variant, FxButtonVariant.primary);
    final left = tester.getRect(discard);
    final right = tester.getRect(keep);
    expect(left.right, lessThan(right.left));
    expect(left.width / right.width, closeTo(2 / 3, .02));
    expect(left.height, greaterThanOrEqualTo(44));
    expect(right.height, greaterThanOrEqualTo(44));
    final dialog = tester.widget<ShadDialog>(find.byType(ShadDialog));
    expect(dialog.removeBorderRadiusWhenTiny, isFalse);
    expect(dialog.radius,
        const BorderRadius.all(Radius.circular(SlowlightRadius.xl)));

    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(discarded, isFalse);
    expect(find.text('放弃未保存的修改？'), findsNothing);

    await tester.tap(find.text('编辑草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(discarded, isTrue);
    await disposeFxTestHost(tester);
  });


  testWidgets('Android 数据模式确认使用左 40% 取消、右 60% 确认', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? confirmed;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => FxButton(
            label: '切换数据模式',
            onPressed: () async {
              confirmed = await FxDialog.confirm(
                context: context,
                title: '切换为本地数据？',
                content: '仅改变数据来源，不自动迁移或删除记录。',
                confirmText: '确认切换',
                mobilePairedActions: true,
                supportingText: '不会自动迁移、合并或删除记录。',
              );
            },
          ),
        ),
      ),
    ));

    Future<void> open() async {
      await tester.tap(find.text('切换数据模式'));
      await tester.pumpAndSettle();
    }

    await open();
    final cancel = find.byKey(const ValueKey('fx.dialog.cancel'));
    final confirm = find.byKey(const ValueKey('fx.dialog.confirm'));
    expect(find.byKey(const ValueKey('fx.dialog.pairedActions')),
        findsOneWidget);
    expect(find.text('不会自动迁移、合并或删除记录。'), findsOneWidget);
    expect(tester.widget<FxButton>(cancel).variant, FxButtonVariant.outline);
    expect(tester.widget<FxButton>(confirm).variant, FxButtonVariant.primary);
    final left = tester.getRect(cancel);
    final right = tester.getRect(confirm);
    expect(left.right, lessThan(right.left));
    expect(left.width / right.width, closeTo(2 / 3, .02));
    expect(left.height, greaterThanOrEqualTo(44));
    expect(right.height, greaterThanOrEqualTo(44));
    expect(tester.widget<ShadDialog>(find.byType(ShadDialog)).closeIcon,
        isA<SizedBox>());

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await open();
    await tester.tap(find.text('确认切换'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 草稿确认仍使用原有桌面危险确认布局', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(builder: (context) => FxButton(
          label: '编辑草稿',
          onPressed: () => FxDialog.confirm(
            context: context,
            title: '放弃未保存的修改？',
            content: '未保存内容将丢失。',
            confirmText: '放弃修改',
            destructive: true,
            draftDiscard: true,
          ),
        )),
      ),
    ));

    await tester.tap(find.text('编辑草稿'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fx.dialog.draftActions')), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('放弃修改'), findsOneWidget);
    final discard = find.widgetWithText(FxButton, '放弃修改');
    expect(tester.widget<FxButton>(discard).variant, FxButtonVariant.destructive);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await disposeFxTestHost(tester);
  });

  testWidgets('Android FxDialog 使用 Android 语义排版', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(buildHost());
    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('删除任务')).style?.fontSize,
      SlowlightTypography.cardTitleSize,
    );
    expect(
      tester.widget<Text>(find.text('确定删除吗？')).style?.fontSize,
      SlowlightTypography.secondarySize,
    );
    expect(
      tester.widget<Text>(find.text('删除')).style?.fontSize,
      SlowlightTypography.buttonSize,
    );

    // A short confirmation uses its visible Cancel action, not a second X.
    expect(tester.widget<ShadDialog>(find.byType(ShadDialog)).closeIcon,
        isA<SizedBox>());

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await disposeFxTestHost(tester);
  });
}
