import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/repositories/reflection_repository.dart';
import 'package:slowlight/screens/today_review_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

class _NoHabits extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => const [];
}

class _ControlledReflections extends ReflectionRepository {
  int calls = 0;
  final Completer<ReflectionEntry> pending = Completer<ReflectionEntry>();

  @override
  Future<List<ReflectionEntry>> recent({int limit = 20}) async => const [];

  @override
  Future<ReflectionEntry> create({
    required String content,
    String entryType = 'reflection',
    String? questionId,
    String? dimensionKey,
    Map<String, dynamic> context = const {},
    List<int> tagIds = const [],
  }) {
    calls++;
    return pending.future;
  }
}

void main() {
  Widget review(_ControlledReflections repository, {
    List<Map<String, dynamic>> questions = const [],
  }) => buildFxTestHost(
    home: Scaffold(body: TodayReviewScreen(
      reflectionRepository: repository,
      habitRepository: _NoHabits(),
      reviewLoader: () async => {
        'facts': <String, dynamic>{},
        'patterns': <String, dynamic>{},
        'questions': questions,
      },
    )),
  );

  testWidgets('Android 回顾标题卡外展示，空问题保留且工具集中到底部',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(_ControlledReflections()));
    await tester.pumpAndSettle();

    expect(find.text('回看事实，留下自己的理解'), findsOneWidget);
    for (final title in ['今日概况', '发生过的事', '留给今天的一句话']) {
      expect(find.text(title), findsOneWidget);
      expect(find.descendant(
        of: find.byType(FxCard),
        matching: find.text(title),
      ), findsNothing);
    }
    expect(find.byKey(const ValueKey('review.mobile.questions.quiet')),
        findsOneWidget);
    expect(find.text('今天还没有留下记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('review.mobile.related')),
        findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('每周回顾'), findsOneWidget);
    expect(find.text('时间分配'), findsOneWidget);
    expect(find.byType(FxInput), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 有待回应问题时也不能隐藏自由记录草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(
      _ControlledReflections(),
      questions: [
        {'id': 'real-question-1', 'content': '今天有什么值得记住的事？'},
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('今天有什么值得记住的事？'), findsOneWidget);
    expect(find.text('留给今天的一句话'), findsOneWidget);
    expect(find.byType(FxInput), findsNWidgets(2));
    expect(find.text('保存记录'), findsOneWidget);
    expect(find.text('保存回应'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('回顾记录保存过程中连续点击只会创建一次', (tester) async {
    final repository = _ControlledReflections();
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FxInput).first, '今天尝试了一件新事');
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    await tester.pump();
    expect(find.text('保存中…'), findsOneWidget);
    expect(repository.calls, 1);
    repository.pending.complete(ReflectionEntry(
      id: 31,
      entryType: 'reflection',
      content: '今天尝试了一件新事',
      createdAt: DateTime(2026),
    ));
    await tester.pump();
    expect(repository.calls, 1);
    await disposeFxTestHost(tester);
  });

  testWidgets('无法确认是否保存时保留草稿，明确核对后才能重新提交', (tester) async {
    final repository = _ControlledReflections();
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(review(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FxInput).first, '想保留的草稿');
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    repository.pending.completeError(StateError('服务器响应未知'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('保存结果尚未确认'), findsOneWidget);
    expect(find.text('已核对，允许重新保存'), findsOneWidget);
    expect(find.text('想保留的草稿'), findsOneWidget);
    expect(repository.calls, 1);
    await disposeFxTestHost(tester);
  });
}
