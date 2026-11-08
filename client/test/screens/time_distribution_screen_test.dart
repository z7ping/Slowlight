import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/time_distribution_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('P13 刷新失败保留已确认的时间分配与原位重试', (tester) async {
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        dataLoader: () async {
          if (++reads == 1) {
            return {
              'total_min': 90,
              'tags': <Map<String, dynamic>>[
                {'name': '深度工作', 'total_min': 90, 'percent': 100},
              ],
              'by_day': <Map<String, dynamic>>[],
            };
          }
          throw StateError('read failed');
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('深度工作'), findsOneWidget);
    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('深度工作'), findsOneWidget);
    expect(find.text('时间分配刷新未确认，以下为上次已载入记录。'),
        findsOneWidget);
    expect(find.text('时间分配暂时不可用'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P13 迟到的旧刷新结果不能覆盖最新时间分配', (tester) async {
    final old = Completer<Map<String, dynamic>>();
    final latest = Completer<Map<String, dynamic>>();
    var reads = 0;
    Map<String, dynamic> data(String name) => {
      'total_min': 30,
      'tags': <Map<String, dynamic>>[
        {'name': name, 'total_min': 30, 'percent': 100},
      ],
      'by_day': <Map<String, dynamic>>[],
    };
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        dataLoader: () {
          if (++reads == 1) return Future.value(data('初始分类'));
          if (reads == 2) return old.future;
          return latest.future;
        },
      )),
    ));
    await tester.pumpAndSettle();
    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh));
    final stale = refresh.onRefresh();
    final newer = refresh.onRefresh();
    await tester.pump();
    expect(find.text('初始分类'), findsOneWidget);
    latest.complete(data('最新分类'));
    await newer;
    await tester.pump();
    old.complete(data('过期分类'));
    await stale;
    await tester.pumpAndSettle();
    expect(find.text('最新分类'), findsOneWidget);
    expect(find.text('过期分类'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P13 有专注分钟但没有标签不展示暂无专注', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        dataLoader: () async => {
          'total_min': 50,
          'tags': <Map<String, dynamic>>[],
          'by_day': <Map<String, dynamic>>[],
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('当前专注尚无可确认的分类'), findsOneWidget);
    expect(find.text('暂无专注数据'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('P13 Android 真实今日专注、未分类、双 KPI 及进入专注导航', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final selected = <TimeDistributionDestination>[];
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        titleProvidedByShell: true,
        onNavigate: (destination) async => selected.add(destination),
        dataLoader: () async {
          reads++;
          return {
            'total_min': 75,
            'total_work_seconds': 4500,
            'unclassified_work_seconds': 900,
            'tags': <Map<String, dynamic>>[
              {
                'tag_id': 1, 'name': '深度工作', 'work_seconds': 3600,
                'total_min': 60, 'percent': 80,
              },
            ],
            'by_day': <Map<String, dynamic>>[
              {
                'date': day, 'total_min': 75, 'work_seconds': 4500,
                'work_count': 3,
              },
            ],
          };
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('专注时间分配'), findsOneWidget);
    expect(find.text('今日已记录专注'), findsOneWidget);
    expect(find.textContaining('75'), findsWidgets);
    expect(find.text('未分类'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timedist.kpi.focus')));
    await tester.pumpAndSettle();
    expect(selected.last, TimeDistributionDestination.focus);
    expect(reads, 2); // Focus return refreshes allocation.
    await tester.tap(find.byKey(const ValueKey('timedist.kpi.tags')));
    expect(selected.last, TimeDistributionDestination.tags);
    await tester.ensureVisible(find.text('进入专注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入专注'));
    await tester.pumpAndSettle();
    expect(selected.last, TimeDistributionDestination.focus);
    expect(reads, 3);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P13 未返回今日事实不能显示 0 分钟', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        dataLoader: () async => {
          'total_min': 25,
          'tags': <Map<String, dynamic>>[],
          'by_day': <Map<String, dynamic>>[
            {'date': '2000-01-01', 'work_count': 1},
          ],
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('未分类 · 25 分钟'), findsOneWidget);
    expect(find.text('当前专注尚无可确认的分类'), findsOneWidget);
    expect(find.text('0 分钟 · 1 次'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P13 大字窄屏：指标可读、详情入口可滚动', (tester) async {
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 680),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(
          body: TimeDistributionScreen(
            onNavigate: (_) async {},
            dataLoader: () async => {
              'total_min': 0,
              'total_work_seconds': 0,
              'unclassified_work_seconds': 0,
              'tags': <Map<String, dynamic>>[],
              'by_day': <Map<String, dynamic>>[],
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('timedist.kpi.focus')), findsOneWidget);
    await tester.ensureVisible(find.text('进入专注'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P13 非法来源不会覆盖上次核对的分类', (tester) async {
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        dataLoader: () async {
          if (++reads == 1) {
            return {
              'total_min': 30,
              'tags': <Map<String, dynamic>>[
                {'name': '认知', 'total_min': 30, 'percent': 100},
              ],
              'by_day': <Map<String, dynamic>>[],
            };
          }
          return {'total_min': 0}; // Malformed payload is not zero facts.
        },
      )),
    ));
    await tester.pumpAndSettle();
    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh));
    await refresh.onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('认知'), findsOneWidget);
    expect(find.text('时间分配刷新未确认，以下为上次已载入记录。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('03 时间分配错误状态可重试，成功后使用统一标签术语', (tester) async {
    var attempts = 0;
    Future<Map<String, dynamic>> load() async {
      attempts++;
      if (attempts == 1) throw StateError('offline');
      return {
        'total_min': 0,
        'tags': <Map<String, dynamic>>[],
        'by_day': <Map<String, dynamic>>[],
      };
    }

    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: TimeDistributionScreen(dataLoader: load),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('时间分配暂时不可用'), findsOneWidget);
    expect(find.text('暂无专注数据'), findsNothing);

    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('标签分布'), findsOneWidget);
    expect(find.text('时间分配暂时不可用'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
