import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/tag.dart';
import 'package:slowlight/models/task_filter_sort.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/widgets/task_filter_sort_sheet.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('X03 标签加载失败明确可重试，恢复后保留原筛选条件', (tester) async {
    var reads = 0;
    final current = const TaskFilterSort(filterTagId: 9);
    final now = DateTime(2026, 11, 8);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: TaskFilterSortSheet(
            current: current,
            lists: [
              TodoList(
                id: 1, name: '收集箱',
                isInbox: true, color: '#808080', createdAt: now,
              ),
            ],
            tagsLoader: () async {
              if (++reads == 1) throw StateError('标签暂时不可达');
              return [
                Tag(
                  id: 9, name: '团队',
                  color: '#0075de', createdAt: now,
                ),
              ];
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('标签读取失败，已选择的条件仍保留'), findsOneWidget);
    expect(find.text('暂无标签'), findsNothing);

    await tester.ensureVisible(find.text('重试标签'));
    await tester.tap(find.text('重试标签'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('团队'), findsOneWidget);
    expect(find.text('标签读取失败，已选择的条件仍保留'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
