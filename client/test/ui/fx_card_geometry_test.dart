import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/theme_manager.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final dark in [false, true]) {
      testWidgets(
        '${platform.name} ${dark ? '暗色' : '亮色'} FxCard 标准/紧凑内边距契约',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);

          await tester.pumpWidget(
            buildFxTestHost(
              theme: dark ? ThemeManager.darkTheme : ThemeManager.lightTheme,
              shadTheme: dark ? ThemeManager.shadDark : ThemeManager.shadLight,
              home: const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FxCard(
                        key: ValueKey('standard'),
                        child: SizedBox(key: ValueKey('standard-body'), width: 100, height: 24),
                      ),
                      FxCard(
                        key: ValueKey('compact'),
                        padding: EdgeInsets.all(14),
                        child: SizedBox(key: ValueKey('compact-body'), width: 100, height: 24),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          for (final entry in [
            ('standard', 16.0),
            ('compact', 14.0),
          ]) {
            final card = find.byKey(ValueKey(entry.$1));
            expect(card, findsOneWidget);
            final padding = fxCardSurfacePadding(tester, card);
            expect(padding, EdgeInsets.all(entry.$2));
          }
          expect(tester.takeException(), isNull);
          await disposeFxTestHost(tester);
        },
      );
    }
  }
}
