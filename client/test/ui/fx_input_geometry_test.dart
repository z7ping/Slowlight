import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/theme_manager.dart';

import '../support/fx_test_host.dart';

void main() {
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
                  child: child,
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

            final fields = find.byType(ShadInput);
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

  testWidgets('搜索清空按钮出现和消失不引起输入框高度跳动', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var showClear = false;
    await tester.pumpWidget(
      buildFxTestHost(
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
                TextButton(
                  onPressed: () => setState(() => showClear = true),
                  child: const Text('输入文字'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final input = find.byType(ShadInput);
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
