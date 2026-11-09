import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  test('异常信息提取短中文业务原因，技术栈不暴露给用户', () {
    expect(FxNotice.readableError(Exception('登录账号已被使用')), '登录账号已被使用');
    expect(FxNotice.readableError(StateError('原密码不正确')), '原密码不正确');
    expect(
      FxNotice.readableError('ClientException with SocketException: Connection refused'),
      '操作未完成，请稍后重试或到应用诊断查看记录',
    );
    expect(
      FxNotice.readableError('Exception: server error\\n#0 stack'),
      '操作未完成，请稍后重试或到应用诊断查看记录',
    );
  });

  testWidgets('Android 长错误仅使用 Sonner，不再打开二次详情弹窗', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 32);
    tester.view.viewPadding = const FakeViewPadding(bottom: 32);
    addTearDown(tester.view.reset);

    final details = List.filled(
      60,
      'ClientException with SocketException: Connection refused',
    ).join('\n');

    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FxButton(
                label: '触发失败',
                onPressed: () => FxNotice.errorWithDetails(
                  context,
                  '登录失败',
                  details,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发失败'));
    // 首帧创建通知并启动入场动画，再推进动画时间。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('登录失败'), findsOneWidget);
    expect(find.text(details), findsNothing);
    expect(find.text('查看详情'), findsNothing);
    expect(find.text('操作未完成，请稍后重试或到应用诊断查看记录'), findsOneWidget);
    expect(fxDialogSurfaceFinder(), findsNothing);
    final toast = fxToastFinder().last;
    expect(tester.getRect(toast).bottom, lessThanOrEqualTo(768));
    expect(tester.takeException(), isNull);

    await disposeFxTestHost(tester);
  });

  testWidgets('登录成功通知在替换登录页后仍能显示', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: Builder(
            builder: (context) => FxButton(
              label: '模拟 GitHub 登录完成',
              onPressed: () {
                final notice = FxNotice.capture(context);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('首页')),
                    ),
                  ),
                );
                notice.show(
                  'GitHub 登录成功',
                  description: '已进入云端模式，可在侧边栏查看同步状态',
                  variant: FxNoticeVariant.success,
                  duration: const Duration(seconds: 4),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('模拟 GitHub 登录完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('GitHub 登录成功'), findsOneWidget);
    expect(find.text('已进入云端模式，可在侧边栏查看同步状态'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('设置页弹出登录后，返回页面仍能看到成功通知', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: Builder(
            builder: (context) => FxButton(
              label: '从设置打开登录',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => Scaffold(
                    body: Builder(
                      builder: (loginContext) => FxButton(
                        label: '模拟登录完成',
                        onPressed: () {
                          final notice = FxNotice.capture(loginContext);
                          Navigator.of(loginContext).pop(true);
                          notice.show(
                            '登录成功',
                            variant: FxNoticeVariant.success,
                            duration: const Duration(seconds: 4),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('从设置打开登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模拟登录完成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('从设置打开登录'), findsOneWidget);
    expect(find.text('登录成功'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('Android 普通提示在顶部，撤销在底栏上方且避让键盘', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(builder: (context) => Column(children: [
          FxButton(label: '顶部通知', onPressed: () =>
              FxNotice.show(context, '普通提示')),
          FxButton(label: '底部撤销', onPressed: () =>
              FxNotice.show(
                context,
                '任务已完成',
                action: FxNoticeAction(label: '撤销', onPressed: () {}),
                placement: FxNoticePlacement.undo,
              )),
        ])),
      ),
    ));

    await tester.tap(find.text('顶部通知'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final topToast = find.ancestor(
      of: find.text('普通提示'),
      matching: fxToastFinder(),
    );
    expect(tester.getRect(topToast).top, lessThan(160));

    await tester.tap(find.text('底部撤销'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final undoToast = find.ancestor(
      of: find.text('任务已完成'),
      matching: fxToastFinder(),
    );
    expect(tester.getRect(undoToast).top, greaterThan(500));
    expect(tester.getRect(undoToast).bottom, lessThan(740));
    expect(find.text('普通提示'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.getRect(undoToast).bottom, lessThan(510));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 普通提示在右上，连续触发替换旧提示', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(builder: (context) => Column(children: [
        FxButton(label: '第一次', onPressed: () => FxNotice.show(context, '旧提示')),
        FxButton(label: '第二次', onPressed: () => FxNotice.show(context, '新提示')),
      ]))),
    ));

    await tester.tap(find.text('第一次'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('第二次'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('旧提示'), findsNothing);
    final currentToast = find.ancestor(
      of: find.text('新提示'),
      matching: fxToastFinder(),
    );
    expect(currentToast, findsOneWidget);
    expect(tester.getRect(currentToast).top, lessThan(120));
    expect(tester.getRect(currentToast).right, greaterThan(1000));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
