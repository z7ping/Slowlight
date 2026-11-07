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
}
