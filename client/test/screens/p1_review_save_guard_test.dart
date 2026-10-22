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
  Widget review(_ControlledReflections repository) => buildFxTestHost(
    home: Scaffold(body: TodayReviewScreen(
      reflectionRepository: repository,
      habitRepository: _NoHabits(),
      reviewLoader: () async => {
        'facts': <String, dynamic>{},
        'patterns': <String, dynamic>{},
        'questions': <Map<String, dynamic>>[],
      },
    )),
  );

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
