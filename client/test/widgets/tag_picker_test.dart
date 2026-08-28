import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/tag_picker.dart';
import 'package:slowlight/models/tag.dart';

void main() {
  group('TagPicker', () {
    group('加载状态', () {
      testWidgets('初始显示加载指示器', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TagPicker(selectedTags: [], onChanged: (_) {}),
          ),
        ));

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('加载中不显示 Wrap 布局', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TagPicker(selectedTags: [], onChanged: (_) {}),
          ),
        ));

        expect(find.byType(SizedBox), findsOneWidget);
        expect(find.byType(Wrap), findsNothing);
      });
    });

    group('参数传递', () {
      testWidgets('selectedTags 为空时不报错', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TagPicker(selectedTags: [], onChanged: (_) {}),
          ),
        ));
        await tester.pump();

        expect(find.byType(TagPicker), findsOneWidget);
      });

      testWidgets('selectedTags 有值时不报错', (tester) async {
        final tags = [
          Tag(id: 1, name: '测试', color: '#ff0000', createdAt: DateTime(2026)),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TagPicker(selectedTags: tags, onChanged: (_) {}),
          ),
        ));
        await tester.pump();

        expect(find.byType(TagPicker), findsOneWidget);
      });

      testWidgets('多个 selectedTags 不报错', (tester) async {
        final tags = [
          Tag(id: 1, name: 'A', color: '#ff0000', createdAt: DateTime(2026)),
          Tag(id: 2, name: 'B', color: '#00ff00', createdAt: DateTime(2026)),
          Tag(id: 3, name: 'C', color: '#0000ff', createdAt: DateTime(2026)),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TagPicker(selectedTags: tags, onChanged: (_) {}),
          ),
        ));
        await tester.pump();

        expect(find.byType(TagPicker), findsOneWidget);
      });
    });

    group('onChanged 回调', () {
      testWidgets('onChanged 回调不为 null 时不报错', (tester) async {
        List<Tag>? received;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TagPicker(
              selectedTags: [],
              onChanged: (tags) => received = tags,
            ),
          ),
        ));
        await tester.pump();

        expect(find.byType(TagPicker), findsOneWidget);
        expect(received, isNull);
      });
    });
  });
}
