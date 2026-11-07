import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/task_tool_screen.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';

import '../support/fx_test_host.dart';

void main() {
  test('初始与退出登录必须保留 AuthGate，不得创建裸登录根路由', () async {
    final main = await File('lib/main.dart').readAsString();
    final login = await File('lib/screens/login_screen.dart').readAsString();
    final settings = await File('lib/screens/settings_screen.dart').readAsString();

    expect(main, contains('home: const AuthGate()'));
    expect(login, isNot(contains('Navigator.pushReplacement(')));
    expect(settings,
        contains('MaterialPageRoute(builder: (_) => const AuthGate())'));
    expect(
      RegExp(
        r'pushAndRemoveUntil\(\s*MaterialPageRoute\(builder: \(_\) => const LoginScreen\(',
      ).hasMatch(settings),
      isFalse,
    );
  });

  test('GitHub 凭据已保存时只重试本地切云端，不重复授权', () async {
    final login = await File('lib/screens/login_screen.dart').readAsString();
    final retryStart = login.indexOf('Future<void> _retryGitHubCloudMode()');
    final retryEnd = login.indexOf('Future<void> _stopGitHubWaiting()', retryStart);
    expect(retryStart, greaterThanOrEqualTo(0));
    expect(retryEnd, greaterThan(retryStart));
    final retryBody = login.substring(retryStart, retryEnd);
    expect(retryBody, contains('await AuthService.isLoggedIn()'));
    expect(retryBody, contains('_enterCloudAfterGitHub(isCurrent)'));
    expect(retryBody, isNot(contains('GitHubSignIn.signIn(')));

    final modeStart = login.indexOf('Future<void> _enterCloudAfterGitHub(');
    expect(modeStart, greaterThanOrEqualTo(0));
    final modeBody = login.substring(modeStart, retryStart);
    expect(modeBody, contains('await DataModeManager().setCloud()'));
    expect(modeBody, contains('authStateNotifier.value'));
    expect(modeBody, contains('请重试进入云端，不需要重复授权'));
    expect(login, contains('label: _githubCredentialsSaved'));
    expect(login, contains('? _retryGitHubCloudMode'));
  });

  test('已保存的账号/注册凭据只重试云端模式，不重复登录或注册', () async {
    final login = await File('lib/screens/login_screen.dart').readAsString();
    final start = login.indexOf('Future<void> _retryStoredCredentialsCloudMode()');
    final end = login.indexOf('Future<void> _loginWithGitHub(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final retry = login.substring(start, end);
    expect(retry, contains('await AuthService.isLoggedIn()'));
    expect(retry, contains('await DataModeManager().setCloud()'));
    expect(retry, contains('authStateNotifier.value'));
    expect(retry, isNot(contains('AuthService.register(')));
    expect(retry, isNot(contains('AuthService.login(')));
    expect(retry, contains('_view = _LoginView.password'));
    expect(login, contains('if (_credentialsSavedForCloud)'));
    expect(login, contains('login.credentials_cloud_error'));
    expect(login, contains("'重试进入云端'"));
  });

  test('本地模式冷启动 GitHub 授权取消后复查根门禁，恢复原工作台', () async {
    final main = await File('lib/main.dart').readAsString();
    final login = await File('lib/screens/login_screen.dart').readAsString();

    expect(main, contains('returnToLocalOnCancel: _pendingGitHubLogin'));
    expect(main, contains('DataModeManager().isLocal'));
    final cancelStart = login.indexOf('Future<void> _stopGitHubWaiting()');
    final cancelEnd = login.indexOf('Future<void> _useLocal()', cancelStart);
    expect(cancelStart, greaterThanOrEqualTo(0));
    expect(cancelEnd, greaterThan(cancelStart));
    final cancel = login.substring(cancelStart, cancelEnd);
    expect(cancel, contains('await GitHubSignIn.cancelPendingAuthorization()'));
    expect(cancel.indexOf('await GitHubSignIn.cancelPendingAuthorization()'),
        lessThan(cancel.indexOf('authStateNotifier.value =')));
    expect(cancel, contains('if (widget.returnToLocalOnCancel)'));
    expect(cancel, isNot(contains('DataModeManager().setLocal()')));
    expect(cancel, isNot(contains('Navigator.pushReplacement(')));
  });

  test('注册结果未知后主操作转为登录核对，不重复调用注册接口', () async {
    final login = await File('lib/screens/login_screen.dart').readAsString();
    final submitStart = login.indexOf('Future<void> _submit() async');
    final submitEnd = login.indexOf('Future<void> _retryStoredCredentialsCloudMode()',
        submitStart);
    expect(submitStart, greaterThanOrEqualTo(0));
    expect(submitEnd, greaterThan(submitStart));
    final submit = login.substring(submitStart, submitEnd);
    expect(submit, contains('if (!_isLogin && _registrationNeedsVerification)'));
    expect(submit.indexOf('if (!_isLogin && _registrationNeedsVerification)'),
        lessThan(submit.indexOf('await AuthService.register(')));
    expect(submit, contains('_open(_LoginView.password);'));
    expect(submit, contains('setState(() => _registrationNeedsVerification = true)'));
    expect(login, contains('login.registration_verify'));
    expect(login, contains("'前往登录核对'"));
  });

  test('P01 首次使用主流程：启动失败可见、四入口同一根门禁收口', () async {
    final main = await File('lib/main.dart').readAsString();
    final login = await File('lib/screens/login_screen.dart').readAsString();
    final github = await File('lib/services/github_sign_in.dart').readAsString();
    final mode = await File('lib/services/data_mode_manager.dart').readAsString();

    final bootStart = main.indexOf('Future<void> main() async');
    final gateStart = main.indexOf('class _AuthGateState');
    expect(bootStart, greaterThanOrEqualTo(0));
    expect(gateStart, greaterThan(bootStart));
    final boot = main.substring(bootStart, gateStart);
    expect(boot, contains("source: 'startup_data_mode'"));
    expect(boot, contains('runApp(const MyApp())'));

    final gate = main.substring(gateStart);
    expect(gate, contains('await DataModeManager().load()'));
    expect(gate, contains('await AuthService.initLocalUser()'));
    expect(gate, contains('await AuthService.isLoggedIn()'));
    expect(gate, contains('GitHubSignIn.hasPendingAuthorization()'));
    expect(gate, contains('returnToLocalOnCancel: _pendingGitHubLogin'));
    expect(gate, contains("title: '身份状态检查失败'"));
    expect(gate, contains('onPressed: _checkAuth'));
    expect(gate, contains('const HomeScreen()'));

    final submit = login.substring(
      login.indexOf('Future<void> _submit() async'),
      login.indexOf('Future<void> _retryStoredCredentialsCloudMode()'),
    );
    expect(submit, contains('await AuthService.login('));
    expect(submit, contains('await AuthService.register('));
    expect(submit, contains('await DataModeManager().setCloud()'));
    expect(submit, contains('authStateNotifier.value'));

    final local = login.substring(
      login.indexOf('Future<void> _useLocal() async'),
      login.indexOf('void _finish(', login.indexOf('Future<void> _useLocal() async')),
    );
    expect(local, contains('await DataModeManager().setLocal()'));
    expect(local, contains('await AuthService.initLocalUser()'));
    expect(local, contains('authStateNotifier.value'));

    expect(login, contains('await GitHubSignIn.signIn('));
    expect(login, contains('await _enterCloudAfterGitHub(isCurrent)'));
    expect(github, contains('await GitHubOAuthPending.save(pending)'));
    expect(github, contains('await AuthService.completeOAuthLogin('));
    expect(github, contains("'mode': 'reliable'"));
    expect(github, contains("'mode': 'ack'"));
    expect(mode, contains("throw StateError('数据模式持久化失败')"));
  });

  test('旧首页、侧栏与维度字段不得悄悄重返正式业务调用链', () async {
    const compatibilityFiles = {
      'lib/screens/home_drawer.dart': 'HomeDrawer',
      'lib/screens/home_today_body.dart': 'HomeTodayBody',
      'lib/widgets/task_dimension_field.dart': 'TaskDimensionField',
    };
    final usage = <String>[];
    await for (final entry in Directory('lib').list(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      final name = entry.path.replaceAll('\\', '/');
      if (compatibilityFiles.containsKey(name)) continue;
      final source = await entry.readAsString();
      for (final symbol in compatibilityFiles.values) {
        if (RegExp('\\b$symbol\\b').hasMatch(source)) {
          usage.add('$name: $symbol');
        }
      }
    }
    expect(
      usage,
      isEmpty,
      reason: '非活动兼容文件仅保留历史兼容，不得以第二套正式 UI 重新引入',
    );
  });

  testWidgets('桌面选择任务后在原工作区查看详情，关闭后保留列表', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final task = Task(
      id: 1, listId: 1, title: '待查看的任务', priority: 'none',
      isCompleted: false, createdAt: DateTime(2026, 10, 24),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataLoader: () async => <dynamic>[
        <Task>[task], <Task>[task], <Task>[], <TodoList>[],
      ])),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(task.title).first);
    // 详情立即可用；标签的独立异步加载不应成为选中任务的等待条件。
    await tester.pump();
    final detail = find.byType(TaskDetailSheet);
    expect(detail, findsOneWidget);
    expect(tester.widget<TaskDetailSheet>(detail).sidePanel, isTrue);
    expect(find.ancestor(of: detail, matching: find.byType(TaskToolScreen)),
        findsOneWidget);
    tester.widget<TaskDetailSheet>(detail).onClose!();
    await tester.pumpAndSettle();
    expect(detail, findsNothing);
    expect(find.text(task.title), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
