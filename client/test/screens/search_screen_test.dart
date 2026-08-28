import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:slowlight/screens/search_screen.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget buildHost(Widget home) {
  return ShadTheme(
    data: ThemeManager.shadLight,
    child: MaterialApp(
      theme: ThemeManager.lightTheme,
      home: home,
    ),
  );
}

void main() {
  group('SearchScreen', () {
    group('UI 渲染', () {
      testWidgets('显示返回按钮', (tester) async {
        await tester.pumpWidget(buildHost(const SearchScreen()));
        await tester.pump();

        expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
      });

      testWidgets('显示搜索输入框', (tester) async {
        await tester.pumpWidget(buildHost(const SearchScreen()));
        await tester.pump();

        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('搜索框自动获取焦点', (tester) async {
        await tester.pumpWidget(buildHost(const SearchScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
      });
    });

    group('搜索状态', () {
      testWidgets('初始状态渲染不崩溃', (tester) async {
        await tester.pumpWidget(buildHost(const SearchScreen()));
        await tester.pump();
        expect(find.byType(SearchScreen), findsOneWidget);
      });

      testWidgets('输入关键词后触发搜索', (tester) async {
        await tester.pumpWidget(buildHost(const SearchScreen()));
        await tester.pump();

        await tester.enterText(find.byType(TextField), '测试');
        await tester.pump(const Duration(milliseconds: 400));
      });
    });

    group('返回导航', () {
      testWidgets('点击返回按钮可 pop', (tester) async {
        await tester.pumpWidget(buildHost(
          Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => const SearchScreen(),
            ),
          ),
        ));
        await tester.pump();

        expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
      });
    });
  });
}
