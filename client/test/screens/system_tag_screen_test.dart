import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/observation_tag.dart';
import 'package:slowlight/repositories/observation_tag_repository.dart';
import 'package:slowlight/screens/system_tag_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

ObservationTag _tag(int id, String name) => ObservationTag(
  id: id,
  name: name,
  icon: '📚',
  color: '#1890FF',
);

class _TagReads extends ObservationTagRepository {
  _TagReads(this.reads);
  final List<Future<List<ObservationTag>> Function()> reads;
  int calls = 0;

  @override
  Future<List<ObservationTag>> getAll() => reads[calls++]();

  @override
  Future<Map<int, ObservationTagUsage>> getAssociationUsage(
      List<ObservationTag> tags) async => {
    for (final tag in tags)
      tag.id: (tasks: 0, habits: 0, sessions: 0, reflections: 0),
  };
}

class _TagImpactRepo extends ObservationTagRepository {
  _TagImpactRepo({this.failPreview = false});

  final bool failPreview;
  int deleteCalls = 0;
  int previewCalls = 0;
  ObservationTagUsage? approvedImpact;

  @override
  Future<List<ObservationTag>> getAll() async => [_tag(7, '阅读')];

  @override
  Future<Map<int, ObservationTagUsage>> getAssociationUsage(
      List<ObservationTag> tags) async => {
    for (final tag in tags)
      tag.id: (tasks: 2, habits: 1, sessions: 3, reflections: 4),
  };

  @override
  Future<({int tasks, int habits, int sessions, int reflections})?>
      getDeletionImpact(ObservationTag tag) async {
    previewCalls++;
    if (failPreview) throw StateError('association count unavailable');
    return (tasks: 2, habits: 1, sessions: 3, reflections: 4);
  }

  @override
  Future<void> delete(
    ObservationTag tag, {ObservationTagUsage? expectedImpact}
  ) async {
    approvedImpact = expectedImpact;
    deleteCalls++;
  }

  @override
  Future<ObservationTagDeletionUndo> deleteWithUndo(
    ObservationTag tag, {required ObservationTagUsage expectedImpact}
  ) async {
    approvedImpact = expectedImpact;
    deleteCalls++;
    return ObservationTagDeletionUndo(() async {});
  }
}

class _TagUsageReads extends ObservationTagRepository {
  int countCalls = 0;

  @override
  Future<List<ObservationTag>> getAll() async => [_tag(7, '阅读')];

  @override
  Future<Map<int, ObservationTagUsage>> getAssociationUsage(
      List<ObservationTag> tags) async {
    if (++countCalls == 1) throw StateError('usage temporarily unavailable');
    return {7: (tasks: 1, habits: 0, sessions: 1, reflections: 0)};
  }
}

class _TagDelayedUsage extends ObservationTagRepository {
  final firstUsage = Completer<Map<int, ObservationTagUsage>>();
  int calls = 0;

  @override
  Future<List<ObservationTag>> getAll() async => [_tag(7, '阅读')];

  @override
  Future<Map<int, ObservationTagUsage>> getAssociationUsage(
      List<ObservationTag> tags) {
    if (++calls == 1) return firstUsage.future;
    return Future.value({
      7: (tasks: 2, habits: 0, sessions: 0, reflections: 0),
    });
  }
}

void main() {
  testWidgets('X08 标签删除明确展示已核对关联范围，取消保持数据',
      (tester) async {
    final repository = _TagImpactRepo();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is FxIconButton && widget.tooltip == '删除',
    ));
    await tester.pumpAndSettle();
    expect(repository.previewCalls, 1);
    expect(find.text('删除标签并解除关联？'), findsOneWidget);
    expect(find.textContaining('任务 2 项、习惯 1 项'), findsOneWidget);
    expect(find.textContaining('专注 3 项、观察/回应 4 项'), findsOneWidget);
    await tester.tap(find.text('保留标签'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);
    expect(find.text('#阅读'), findsOneWidget);
    await disposeFxTestHost(tester);
  });

  testWidgets('X08 标签确认后将用户批准的全部关联范围传入删除', (tester) async {
    final repository = _TagImpactRepo();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is FxIconButton && widget.tooltip == '删除',
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除标签'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 1);
    expect(repository.approvedImpact,
      (tasks: 2, habits: 1, sessions: 3, reflections: 4));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X08 标签删除成功提供真实撤销入口', (tester) async {
    final repo = _TagImpactRepo();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repo)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (w) => w is FxIconButton && w.tooltip == '删除',
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除标签'));
    await tester.pumpAndSettle();
    expect(repo.deleteCalls, 1);
    expect(repo.approvedImpact,
      (tasks: 2, habits: 1, sessions: 3, reflections: 4));
    expect(find.text('撤销'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('原标签及关联已恢复'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X08 关联范围查询失败禁止删除', (tester) async {
    final repository = _TagImpactRepo(failPreview: true);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is FxIconButton && widget.tooltip == '删除',
    ));
    await tester.pumpAndSettle();
    expect(repository.previewCalls, 1);
    expect(repository.deleteCalls, 0);
    expect(find.text('删除标签并解除关联？'), findsNothing);
    await disposeFxTestHost(tester);
  });

  testWidgets('P15 已载入标签刷新失败仍可见，并支持再次重试', (tester) async {
    final repository = _TagReads([
      () async => [_tag(7, '阅读')],
      () async => throw StateError('temporary offline'),
      () async => [_tag(7, '阅读'), _tag(8, '心流')],
    ]);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('#阅读'), findsOneWidget);

    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('#阅读'), findsOneWidget);
    expect(find.text('标签刷新未确认，以下仍为上次已载入的标签。'),
        findsOneWidget);
    expect(find.text('标签加载失败'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(repository.calls, 3);
    expect(find.text('#心流'), findsOneWidget);
    expect(find.text('标签刷新未确认，以下仍为上次已载入的标签。'),
        findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P15 旧请求迟到不会覆盖新标签列表', (tester) async {
    final pending = Completer<List<ObservationTag>>();
    final current = Completer<List<ObservationTag>>();
    final repository = _TagReads([
      () async => [_tag(1, '初始')],
      () => pending.future,
      () => current.future,
    ]);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();
    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh));
    final earlier = refresh.onRefresh();
    final later = refresh.onRefresh();
    await tester.pump();
    expect(find.text('#初始'), findsOneWidget);
    current.complete([_tag(2, '最新')]);
    await later;
    await tester.pump();
    pending.complete([_tag(3, '过期')]);
    await earlier;
    await tester.pumpAndSettle();
    expect(repository.calls, 3);
    expect(find.text('#最新'), findsOneWidget);
    expect(find.text('#过期'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P15 首次标签读取失败明确显示重试而非空标签', (tester) async {
    final repository = _TagReads([
      () async => throw StateError('offline'),
    ]);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('标签加载失败'), findsOneWidget);
    expect(find.text('还没有标签'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('P15 显示已核对关联数量，点击整行进入原有编辑器', (tester) async {
    final repository = _TagImpactRepo();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('关联影响 10 条'), findsOneWidget);
    await tester.tap(find.text('#阅读'));
    await tester.pumpAndSettle();
    expect(find.text('编辑标签'), findsOneWidget);
    expect(find.textContaining('关联影响 10 条'), findsWidgets);
    expect(find.byType(FxInput), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P15 关联读取失败不隐藏标签，可独立重试恢复', (tester) async {
    final repository = _TagUsageReads();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('#阅读'), findsOneWidget);
    expect(find.text('关联未核对'), findsOneWidget);
    expect(find.text('标签关联数量未全部核对，标签本身仍可管理。'), findsOneWidget);
    await tester.tap(find.text('重试关联'));
    await tester.pumpAndSettle();
    expect(repository.countCalls, 2);
    expect(find.textContaining('关联影响 2 条'), findsOneWidget);
    expect(find.text('标签关联数量未全部核对，标签本身仍可管理。'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P15 关联读取迟到不能污染刷新后的标签记录', (tester) async {
    final repository = _TagDelayedUsage();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SystemTagScreen(repository: repository)),
    ));
    await tester.pump();
    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pump();
    repository.firstUsage.complete({
      7: (tasks: 999, habits: 0, sessions: 0, reflections: 0),
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('关联影响 999 条'), findsNothing);
    expect(find.textContaining('关联影响 2 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
