import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:slowlight/widgets/task_schedule_fields.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('明确 maxLines: null 时允许多行编辑，不回退到单行', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: const Scaffold(
          body: FxInput(
            placeholder: '任务描述',
            minLines: 1,
            maxLines: null,
          ),
        ),
      ),
    );
    await tester.pump();
    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.maxLines, isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  // 回归：只验证外框高度不足以发现文字靠上的问题。
  // 同时覆盖占位符与真实输入文字在单行字段中的中心位置。
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('单行输入内容垂直居中：${platform.name} / ${scale}x', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.pumpWidget(buildFxTestHost(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FxInput(placeholder: '任务标题'),
                    FxInput(placeholder: '描述（可选）'),
                    FxInput(placeholder: '带图标', leading: Icon(Icons.search)),
                    FxInput(placeholder: '禁用输入', enabled: false),
                  ],
                ),
              ),
            ),
          ),
        ));
        await tester.pump();

        final fields = find.byType(FxInput);
        final minimum = platform == TargetPlatform.android ? 44.0 : 36.0;
        final expectedPadding = platform == TargetPlatform.android ? 12.0 : 8.0;
        for (final input in tester.widgetList<ShadInput>(find.byType(ShadInput))) {
          expect(input.constraints?.minHeight, minimum);
          expect(input.inputPadding,
              EdgeInsets.symmetric(vertical: expectedPadding));
        }
        for (var index = 0; index < 4; index++) {
          // 防止仅调整文字位置却将输入框压成截图中的细条。
          expect(tester.getSize(fields.at(index)).height,
              greaterThanOrEqualTo(minimum));
          final fieldCenter = tester.getRect(fields.at(index)).center.dy;
          final editable = find.descendant(
            of: fields.at(index),
            matching: find.byType(EditableText),
          );
          final textCenter = tester.getRect(editable).center.dy;
          expect((fieldCenter - textCenter).abs(), lessThanOrEqualTo(2.0),
              reason: '第 ${index + 1} 个输入框文字应垂直居中');
        }

        await tester.enterText(find.byType(EditableText).first, '新建任务');
        await tester.pump();
        final fieldCenter = tester.getRect(fields.first).center.dy;
        final textCenter = tester.getRect(find.byType(EditableText).first).center.dy;
        expect((fieldCenter - textCenter).abs(), lessThanOrEqualTo(2.0));
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          '${platform.name} ${dark ? '暗色' : '亮色'} 字号 ${scale}x：'
          '普通/密码/图标/禁用输入等高',
          (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            await tester.pumpWidget(
              buildFxTestHost(
                theme: dark ? ThemeManager.darkTheme : ThemeManager.lightTheme,
                shadTheme: dark ? ThemeManager.shadDark : ThemeManager.shadLight,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                ),
                home: const Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 300,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FxInput(placeholder: '普通输入'),
                          FxInput(
                            placeholder: '密码',
                            obscureText: true,
                            trailing: FxIconButton(
                              icon: Icons.visibility,
                              tooltip: '显示密码',
                            ),
                          ),
                          FxInput(
                            placeholder: '图标输入',
                            leading: Icon(Icons.search),
                          ),
                          FxInput(
                            placeholder: '禁用输入',
                            enabled: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            final fields = find.byType(FxInput);
            expect(fields, findsNWidgets(4));
            final heights = [
              for (var i = 0; i < 4; i++)
                tester.getSize(fields.at(i)).height,
            ];
            final minimum = platform == TargetPlatform.android ? 44.0 : 36.0;
            for (final height in heights) {
              expect(height, greaterThanOrEqualTo(minimum));
              expect(height, closeTo(heights.first, 0.1));
            }

            await tester.tap(find.byType(FxInput).first);
            await tester.pump();
            expect(tester.getSize(fields.first).height, closeTo(heights.first, 0.1));
            expect(tester.takeException(), isNull);
            await disposeFxTestHost(tester);
          },
        );
      }
    }
  }

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('${platform.name} ${scale}x FxSelect 与 FxInput 共享表单尺寸', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          buildFxTestHost(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FxInput(placeholder: '任务名称'),
                      FxSelect<String>(
                        placeholder: '重复规则',
                        options: [
                          FxSelectOption(value: 'none', label: '不重复'),
                          FxSelectOption(value: 'daily', label: '每天'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final inputHeight = tester.getSize(find.byType(FxInput)).height;
        final selectHeight = tester.getSize(find.byType(FxSelect<String>)).height;
        final trigger = tester.widget<ShadSelect<String>>(find.byType(ShadSelect<String>));
        // 回归：检查真正绘制边框的 ShadSelect 内部留白，
        // 只断言 FxSelect 外层 minHeight 会漏掉截图中的扁平下拉框。
        expect(trigger.padding, EdgeInsets.symmetric(
          horizontal: platform == TargetPlatform.android ? 14 : 12,
          vertical: platform == TargetPlatform.android ? 12 : 8,
        ));
        final minHeight = platform == TargetPlatform.android ? 44.0 : 36.0;
        expect(inputHeight, greaterThanOrEqualTo(minHeight));
        expect(selectHeight, greaterThanOrEqualTo(minHeight));
        if (scale == 1.0) {
          expect(selectHeight, closeTo(inputHeight, 2));
        }
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }


  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('搜索清空显隐不跳高：$platform / $scale', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var showClear = false;
        await tester.pumpWidget(buildFxTestHost(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  FxInput(
                    placeholder: '搜索任务、习惯、回顾…',
                    leading: const Icon(Icons.search),
                    trailing: showClear
                        ? FxIconButton(
                            icon: Icons.close,
                            onPressed: () => setState(() => showClear = false),
                          )
                        : null,
                  ),
                  FxButton(
                    label: '输入文字',
                    onPressed: () => setState(() => showClear = true),
                  ),
                ],
              ),
            ),
          ),
        ));
        await tester.pump();
        final input = find.byType(FxInput);
        final initialHeight = tester.getSize(input).height;
        await tester.tap(find.text('输入文字'));
        await tester.pump();
        expect(tester.getSize(input).height, closeTo(initialHeight, 0.1));
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        expect(tester.getSize(input).height, closeTo(initialHeight, 0.1));
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }


  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('${platform.name} 任务日程四项控件共享同一可视高度', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(buildFxTestHost(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: TaskScheduleFields(
                enabled: true,
                dueDate: DateTime(2026, 10, 22),
                onDateChanged: (_) {},
                dueTime: const TimeOfDay(hour: 9, minute: 30),
                onTimeChanged: (_) {},
                repeatType: 'none',
                onRepeatChanged: (_) {},
                selectedWeekdays: const <int>{},
                onWeekdayToggled: (_) {},
                reminderAdvanceMinutes: -1,
                onReminderChanged: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final pickers = find.byType(FxInkWell);
      expect(pickers, findsNWidgets(2));
      final heights = [
        tester.getSize(pickers.at(0)).height,
        tester.getSize(pickers.at(1)).height,
        tester.getSize(find.byType(FxSelect<String>)).height,
        tester.getSize(find.byType(FxSelect<int>)).height,
      ];
      final minHeight = platform == TargetPlatform.android ? 44.0 : 36.0;
      for (final height in heights) {
        expect(height, greaterThanOrEqualTo(minHeight));
        expect((height - heights.first).abs(), lessThanOrEqualTo(4));
      }
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }
}
