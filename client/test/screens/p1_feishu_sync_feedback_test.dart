import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/repositories/feishu_integration_repository.dart';
import 'package:slowlight/screens/feishu_screen.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../support/fx_test_host.dart';

class _SyncFake implements FeishuIntegrationRepository {
  final Completer<Map<String, dynamic>> reply =
      Completer<Map<String, dynamic>>();
  int allRequests = 0;
  int taskRequests = 0;

  @override
  Future<Map<String, dynamic>> config() async => {
        'configured': true,
        'app_id': 'cli_test',
        'table_url': 'https://example.com/base',
        'tables': {'任务': 't1'},
      };

  @override
  Future<Map<String, dynamic>> syncAll() {
    allRequests++;
    return reply.future;
  }

  @override
  Future<Map<String, dynamic>> syncTasks() async {
    taskRequests++;
    return {'message': '任务已同步'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  testWidgets('飞书部分成功不提示全部成功，且同步期间阻止重复/交叉提交',
      (tester) async {
    await DataModeManager().setLocal();
    final fake = _SyncFake();
    tester.view.physicalSize = const Size(1280, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: FeishuScreen(repository: fake),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('同步全部'));
    await tester.pump();
    expect(fake.allRequests, 1);
    expect(find.text('同步中…'), findsOneWidget);

    // 同步全部运行时，尝试点击单项同步不应发送第二个请求。
    await tester.tap(find.text('任务与清单'));
    await tester.pump();
    expect(fake.taskRequests, 0);
    fake.reply.complete({
      'results': {'任务': 3},
      'errors': ['休息记录：飞书服务暂不可用'],
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('部分同步失败（1 项）'), findsOneWidget);
    expect(fake.allRequests, 1);
    expect(fake.taskRequests, 0);
    await disposeFxTestHost(tester);
  });
}
