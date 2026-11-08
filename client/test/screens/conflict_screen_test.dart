import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/conflict_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

Map<String, dynamic> _conflict(int id, String title) => {
  '_entity_type': 'tasks',
  'id': id,
  'title': title,
};

void main() {
  testWidgets('S14 并行刷新旧响应不得覆盖新冲突列表', (tester) async {
    final earlier = Completer<List<Map<String, dynamic>>>();
    final later = Completer<List<Map<String, dynamic>>>();
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: ConflictScreen(
          conflictsLoader: () {
            final call = ++reads;
            if (call == 1) {
              return Future.value([_conflict(1, '初始冲突')]);
            }
            return call == 2 ? earlier.future : later.future;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('初始冲突'), findsOneWidget);
    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh));
    final slow = refresh.onRefresh();
    final fast = refresh.onRefresh();
    await tester.pump();
    expect(reads, 3);
    later.complete([_conflict(3, '最新冲突')]);
    await fast;
    await tester.pump();
    earlier.complete([_conflict(2, '过期冲突')]);
    await slow;
    await tester.pumpAndSettle();
    expect(find.textContaining('最新冲突'), findsOneWidget);
    expect(find.textContaining('初始冲突'), findsNothing);
    expect(find.textContaining('过期冲突'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('S14 同一冲突的本地和云端决策互斥，不会双重提交', (tester) async {
    final pending = Completer<bool>();
    var writes = 0;
    var reads = 0;
    final row = <String, dynamic>{
      '_entity_type': 'tasks',
      'id': 7,
      'server_id': 19,
      'title': '待确认的任务',
    };
    await tester.pumpWidget(buildFxTestHost(
      home: ConflictScreen(
        conflictsLoader: () async {
          reads++;
          return [row];
        },
        remotePreviewLoader: (_, __) async => {'title': '服务端任务'},
        conflictResolver: (id, {required entityType, required keepLocal}) {
          expect(id, 7);
          expect(entityType, 'tasks');
          expect(keepLocal, true);
          writes++;
          return pending.future;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FxButton, '保留本地版本'));
    await tester.pump();
    expect(writes, 1);
    expect(find.text('处理中…'), findsOneWidget);
    expect(
      tester.widget<FxButton>(
        find.widgetWithText(FxButton, '使用服务端版本'),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<FxButton>(
        find.widgetWithText(FxButton, '处理中…'),
      ).onPressed,
      isNull,
    );

    pending.complete(true);
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(reads, 2);
    expect(find.text('处理中…'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('S14 回执异常必须先重新核对，不能直接重复写入', (tester) async {
    var writes = 0;
    var reads = 0;
    final row = <String, dynamic>{
      '_entity_type': 'tasks',
      'id': 8,
      'server_id': 20,
      'title': '网络中断任务',
    };
    await tester.pumpWidget(buildFxTestHost(
      home: ConflictScreen(
        conflictsLoader: () async {
          reads++;
          return [row];
        },
        remotePreviewLoader: (_, __) async => {'title': '云端版本'},
        conflictResolver: (_, {required entityType, required keepLocal}) async {
          writes++;
          if (writes == 1) throw StateError('connection closed');
          return true;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FxButton, '保留本地版本'));
    await tester.pumpAndSettle();

    expect(writes, 1);
    expect(
      find.byKey(const ValueKey('conflicts.recheck_unknown')),
      findsOneWidget,
    );
    expect(
      tester.widget<FxButton>(
        find.widgetWithText(FxButton, '保留本地版本'),
      ).onPressed,
      isNull,
    );
    expect(
      tester.widget<FxButton>(
        find.widgetWithText(FxButton, '使用服务端版本'),
      ).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('conflicts.recheck_unknown')));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(
      find.byKey(const ValueKey('conflicts.recheck_unknown')),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(FxButton, '保留本地版本'));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
