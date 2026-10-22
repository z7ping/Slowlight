import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../brand.dart';
import '../main.dart' show authStateNotifier;
import '../services/auth_service.dart';
import '../services/app_error_logger.dart';
import '../services/data_mode_manager.dart';
import '../services/github_sign_in.dart';
import '../ui/fx.dart';
import '../ui/widgets/slowlight_logo.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isLogin = true;
  bool _showPasswordForm = false;
  bool _isLoading = false;
  bool _githubAuthorizing = false;
  bool _githubFinishing = false;
  int _githubAttempt = 0;
  String? _githubError;
  bool _githubCanResume = false;
  String _githubStatus = "等待 GitHub 完成授权…";
  bool _deviceFlowEnabled = false;
  String? _githubDeviceCode;
  Uri? _githubVerificationUri;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    GitHubSignIn.deviceFlowAvailable().then((enabled) {
      if (mounted) setState(() => _deviceFlowEnabled = enabled);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted || _isLoading) return;
        final pending = await GitHubSignIn.hasPendingAuthorization();
        if (mounted && !_isLoading && pending) {
          await _loginWithGitHub(resumePending: true);
        }
      } catch (_) {
        // 不允许暂存记录读取故障阻断正常密码登录。
      }
    });
  }

  @override
  void dispose() {
    _githubAttempt++;
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _message('请填写完整信息');
      return;
    }
    if (!_isLogin && _emailController.text.trim().isEmpty) {
      _message('请填写邮箱');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await AuthService.login(
          _usernameController.text.trim(),
          _passwordController.text,
        );
      } else {
        await AuthService.register(
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          nickname: _nicknameController.text.trim().isEmpty
              ? null
              : _nicknameController.text.trim(),
        );
      }
      // 使用密码登录成功后，取消尚未确认的 GitHub 会话，避免下次启动切换账号。
      try {
        await GitHubSignIn.cancelPendingAuthorization();
      } catch (_) {
        // 已完成的账号登录不应被临时授权清理失败撤销。
      }
      await DataModeManager().setCloud();
      authStateNotifier.value = !authStateNotifier.value;
      if (mounted) {
        _finish(
          true,
          successMessage: _isLogin ? '登录成功' : '账号创建成功',
        );
      }
    } catch (e) {
      if (mounted) {
        FxNotice.errorWithDetails(
          context,
          _isLogin ? '登录失败' : '注册失败',
          e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGitHub({
    bool resumePending = false,
    bool useDeviceCode = false,
  }) async {
    if (_isLoading) return;
    final attempt = ++_githubAttempt;
    bool isCurrent() => mounted && attempt == _githubAttempt;
    setState(() {
      _isLoading = true;
      _githubAuthorizing = true;
      _githubFinishing = false;
      _githubStatus = resumePending ? '正在恢复上次 GitHub 授权…' : '等待 GitHub 完成授权…';
      _githubDeviceCode = null;
      _githubVerificationUri = null;
      _githubError = null;
      _githubCanResume = false;
    });
    try {
      final completed = await GitHubSignIn.signIn(
        shouldContinue: () => isCurrent() && _githubAuthorizing,
        resumePending: resumePending,
        useDeviceCode: useDeviceCode,
        onDeviceCode: (code, uri) {
          if (isCurrent() && _githubAuthorizing) {
            setState(() {
              _githubDeviceCode = code;
              _githubVerificationUri = uri;
            });
          }
        },
        onStatus: (status) {
          if (isCurrent() && _githubAuthorizing) {
            setState(() {
              _githubStatus = status;
              _githubFinishing = status == '正在保存登录状态…';
            });
          }
        },
      );
      if (!isCurrent() || !completed) return;
      await DataModeManager().setCloud();
      if (!isCurrent()) return;
      authStateNotifier.value = !authStateNotifier.value;
      if (mounted) _finish(true, successMessage: 'GitHub 登录成功');
    } catch (e) {
      unawaited(
          AppErrorLogger.instance.write(source: 'github_login', error: e));
      if (isCurrent()) {
        final message = GitHubSignIn.describeError(e);
        var canResume = false;
        try {
          canResume = await GitHubSignIn.hasPendingAuthorization();
        } catch (_) {
          // 存储读取失败时仍保留可见错误与重新授权入口。
        }
        if (isCurrent()) {
          setState(() {
            _githubError = message;
            _githubCanResume = canResume;
          });
        }
      }
    } finally {
      if (isCurrent()) {
        setState(() {
          _isLoading = false;
          _githubAuthorizing = false;
        });
      }
    }
  }

  Future<void> _stopGitHubWaiting() async {
    if (_githubFinishing) return;
    final attempt = ++_githubAttempt;
    setState(() {
      _githubAuthorizing = false;
      _isLoading = true;
      _githubError = null;
    });
    try {
      await GitHubSignIn.cancelPendingAuthorization();
    } catch (error) {
      unawaited(
          AppErrorLogger.instance.write(source: 'github_cancel', error: error));
    } finally {
      if (mounted && attempt == _githubAttempt) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _useLocal() async {
    setState(() => _isLoading = true);
    try {
      // 用户主动进入本地模式，必须同步放弃待恢复 GitHub 会话。
      await GitHubSignIn.cancelPendingAuthorization();
      await DataModeManager().setLocal();
      await AuthService.initLocalUser();
      authStateNotifier.value = !authStateNotifier.value;
      if (mounted) _finish(false);
    } catch (e) {
      if (mounted) FxNotice.errorWithDetails(context, '进入本地数据失败', e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _finish(bool value, {String? successMessage}) {
    // 通知宿主在 Navigator 外层，先捕获再跳转，避免登录页销毁后提示丢失。
    final notice = successMessage == null ? null : FxNotice.capture(context);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(value);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
    if (successMessage != null) {
      notice!.show(
        successMessage,
        description: value ? '已进入云端模式，可在侧边栏查看同步状态' : '当前数据保存在本机',
        variant: FxNoticeVariant.success,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void _message(String text) {
    FxNotice.showContent(context, Text(text));
  }


  /// Compact app identity for single-column layouts, not a splash screen.
  Widget _compactBrand(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('login.compact_brand'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SlowlightLogo(size: 40),
        const SizedBox(width: SlowlightSpacing.xl),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kBrandDisplayName,
                  style: SlowlightTypography.cardTitle(context)),
              const SizedBox(height: SlowlightSpacing.xs),
              Text(kBrandTagline,
                  style: SlowlightTypography.caption(context).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  /// On Windows the product identity is a separate column, not a giant
  /// duplicate heading above a vertically stretched phone form.
  Widget _desktopBrand(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('login.desktop_brand'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SlowlightLogo(size: 56),
        const SizedBox(height: SlowlightSpacing.page),
        Text(kBrandDisplayName,
            style: SlowlightTypography.display(context)),
        const SizedBox(height: SlowlightSpacing.md),
        Text(kBrandTagline,
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        const SizedBox(height: SlowlightSpacing.page),
        FxSeparator.horizontal(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: SlowlightSpacing.xxxl),
        Text('记录当下，回看一路走来的自己。',
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }

  Widget _githubWaiting(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = SlowlightTypography.secondary(context).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      key: const ValueKey('login.github_waiting'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const FxCircularProgress(
              strokeWidth: 2,
              constraints: BoxConstraints.tightFor(width: 20, height: 20),
              semanticsLabel: '正在检查授权',
            ),
            const SizedBox(width: SlowlightSpacing.xl),
            Expanded(
              child: Text('正在连接 GitHub',
                  style: SlowlightTypography.sectionTitle(context)),
            ),
          ],
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Text(_githubStatus,
            key: const ValueKey('login.github_status'),
            style: secondary),
        const SizedBox(height: SlowlightSpacing.xs),
        Text('授权完成后会自动登录，无需重复点击。',
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        if (_githubDeviceCode != null &&
            _githubVerificationUri != null) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          SelectableText(
            _githubDeviceCode!,
            key: const ValueKey('login.github_device_code'),
            style: SlowlightTypography.sectionTitle(context),
          ),
          const SizedBox(height: SlowlightSpacing.md),
          Wrap(
            spacing: SlowlightSpacing.md,
            runSpacing: SlowlightSpacing.md,
            children: [
              FxButton(
                key: const ValueKey('login.github_device_copy'),
                label: '复制验证码',
                variant: FxButtonVariant.outline,
                size: FxButtonSize.sm,
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: _githubDeviceCode!));
                  if (mounted) _message('验证码已复制');
                },
              ),
              FxButton(
                key: const ValueKey('login.github_device_open'),
                label: '打开验证页面',
                variant: FxButtonVariant.outline,
                size: FxButtonSize.sm,
                onPressed: () async {
                  final target = _githubVerificationUri;
                  if (target != null &&
                      !await launchUrl(target,
                          mode: LaunchMode.externalApplication) &&
                      mounted) {
                    _message('无法打开 GitHub，请手动访问 github.com/login/device');
                  }
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: SlowlightSpacing.xxxl),
        Wrap(
          spacing: SlowlightSpacing.md,
          runSpacing: SlowlightSpacing.md,
          children: [
            if (theme.platform == TargetPlatform.windows ||
                theme.platform == TargetPlatform.android)
              FxButton(
                key: const ValueKey('login.github_check'),
                label: '检查授权结果',
                variant: FxButtonVariant.outline,
                size: FxButtonSize.sm,
                onPressed: () {
                  if (!GitHubSignIn.checkAuthorizationNow()) {
                    _message('授权会话正在初始化，请稍后重试');
                  }
                },
              ),
            if (_githubDeviceCode == null)
              FxButton(
                key: const ValueKey('login.github_reopen'),
                label: '返回授权页',
                variant: FxButtonVariant.ghost,
                size: FxButtonSize.sm,
                onPressed: () async {
                  try {
                    if (!await GitHubSignIn.reopenAuthorization() && mounted) {
                      _message('无法重新打开授权页，请停止等待后重新授权');
                    }
                  } catch (_) {
                    if (mounted) _message('无法打开浏览器，请检查默认浏览器设置');
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FxButton(
            key: const ValueKey('login.github_cancel'),
            label: '取消授权等待',
            variant: FxButtonVariant.link,
            size: FxButtonSize.sm,
            onPressed: _githubFinishing ? null : _stopGitHubWaiting,
          ),
        ),
      ],
    );
  }

  Widget _githubAction(BuildContext context) {
    final theme = Theme.of(context);
    if (_githubAuthorizing) return _githubWaiting(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_githubError != null) ...[
          Text(
            _githubError!,
            key: const ValueKey('login.github_error'),
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: SlowlightSpacing.md),
        ],
        FxButton(
          key: const ValueKey('login.github_action'),
          label: _githubError == null
              ? '使用 GitHub 继续'
              : _githubCanResume
                  ? '继续检查上次授权'
                  : '重新进行 GitHub 授权',
          expanded: true,
          size: FxButtonSize.lg,
          onPressed: _isLoading
              ? null
              : () => _loginWithGitHub(
                  resumePending: _githubError != null && _githubCanResume),
        ),
        if (_deviceFlowEnabled) ...[
          const SizedBox(height: SlowlightSpacing.xs),
          Align(
            alignment: Alignment.center,
            child: FxButton(
              key: const ValueKey('login.github_device_action'),
              label: '验证码登录（备用）',
              variant: FxButtonVariant.link,
              size: FxButtonSize.sm,
              onPressed: _isLoading
                  ? null
                  : () => _loginWithGitHub(useDeviceCode: true),
            ),
          ),
        ],
      ],
    );
  }

  Widget _passwordFields(BuildContext context) {
    return Column(
      key: const ValueKey('login.password_fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxInput(
          controller: _usernameController,
          enabled: !_isLoading,
          textInputAction: TextInputAction.next,
          label: '账号',
          placeholder: _isLogin ? '邮箱或用户名' : '设置用户名',
        ),
        if (!_isLogin) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          FxInput(
            controller: _emailController,
            enabled: !_isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            label: '邮箱',
            placeholder: '请输入邮箱',
          ),
        ],
        const SizedBox(height: SlowlightSpacing.xxxl),
        FxInput(
          controller: _passwordController,
          enabled: !_isLoading,
          obscureText: _obscurePassword,
          textInputAction:
              _isLogin ? TextInputAction.done : TextInputAction.next,
          onSubmitted: _isLogin ? (_) => _submit() : null,
          label: '密码',
          placeholder: '请输入密码',
          enableSuggestions: false,
          autocorrect: false,
          trailing: FxIconButton(
            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
            onPressed: _isLoading
                ? null
                : () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
            icon: _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
            iconSize: SlowlightIconSize.sm,
          ),
        ),
        if (!_isLogin) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          FxInput(
            controller: _nicknameController,
            enabled: !_isLoading,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            label: '昵称（可选）',
            placeholder: '如何称呼你？',
          ),
        ],
        const SizedBox(height: SlowlightSpacing.xxxl),
        SizedBox(
          key: const ValueKey('login.primary_action'),
          width: double.infinity,
          child: FxButton(
            label: _isLoading
                ? '处理中…'
                : _isLogin
                    ? '登录'
                    : '创建账号',
            size: FxButtonSize.lg,
            expanded: true,
            onPressed: _isLoading ? null : _submit,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginContents(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = SlowlightTypography.secondary(context).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      key: const ValueKey('login.form_panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_isLogin ? '欢迎回来' : '创建账号',
            style: SlowlightTypography.hero(context)),
        const SizedBox(height: SlowlightSpacing.md),
        Text(
          _isLogin
              ? '登录云端，让记录在设备间延续。'
              : '创建云端账号，在不同设备查看自己的记录。',
          style: secondary,
        ),
        const SizedBox(height: SlowlightSpacing.page),
        _githubAction(context),
        if (!_githubAuthorizing) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FxButton(
                key: const ValueKey('login.password_toggle'),
                label: _showPasswordForm ? '收起账号密码' : '使用账号密码',
                variant: FxButtonVariant.link,
                size: FxButtonSize.sm,
                onPressed: _isLoading
                    ? null
                    : () => setState(() {
                        _showPasswordForm = !_showPasswordForm;
                        if (!_showPasswordForm) _isLogin = true;
                      }),
              ),
              if (_isLogin) ...[
                Text('·', style: secondary),
                FxButton(
                  key: const ValueKey('login.switch_mode'),
                  label: '注册账号',
                  variant: FxButtonVariant.link,
                  size: FxButtonSize.sm,
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                          _isLogin = false;
                          _showPasswordForm = true;
                        }),
                ),
              ],
            ],
          ),
          if (_showPasswordForm) ...[
            const SizedBox(height: SlowlightSpacing.xxxl),
            _passwordFields(context),
            if (!_isLogin) ...[
              const SizedBox(height: SlowlightSpacing.md),
              Align(
                alignment: Alignment.center,
                child: FxButton(
                  key: const ValueKey('login.return_login'),
                  label: '已有账号？返回登录',
                  variant: FxButtonVariant.link,
                  size: FxButtonSize.sm,
                  onPressed: _isLoading
                      ? null
                      : () => setState(() => _isLogin = true),
                ),
              ),
            ],
          ],
          const SizedBox(height: SlowlightSpacing.page),
          FxSeparator.horizontal(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: SlowlightSpacing.md),
          FxButton(
            key: const ValueKey('login.local_action'),
            label: '不登录，使用本地数据',
            icon: LucideIcons.smartphone,
            variant: FxButtonVariant.ghost,
            size: FxButtonSize.lg,
            expanded: true,
            onPressed: _isLoading ? null : _useLocal,
          ),
          const SizedBox(height: SlowlightSpacing.xs),
          Text(
            '本地记录只保存在本机，不会自动上传或合并。',
            textAlign: TextAlign.center,
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_githubAuthorizing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _githubAuthorizing && !_githubFinishing) {
          unawaited(_stopGitHubWaiting());
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final splitDesktop =
                  !SlowlightPlatformDensity.usesMobileTouchTargets &&
                  viewport.maxWidth >= SlowlightBreakpoints.desktopMin;
              final contents = _buildLoginContents(context);
              final Widget content;
              if (splitDesktop) {
                content = Row(
                  key: const ValueKey('login.desktop_columns'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 320,
                      child: _desktopBrand(context),
                    ),
                    const SizedBox(width: SlowlightSpacing.page * 2),
                    SizedBox(
                      width: 440,
                      child: FxCard(
                        padding: const EdgeInsets.all(SlowlightSpacing.page),
                        borderRadius: SlowlightRadius.xl,
                        child: contents,
                      ),
                    ),
                  ],
                );
              } else {
                content = ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    key: const ValueKey('login.single_column'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _compactBrand(context),
                      const SizedBox(height: SlowlightSpacing.page),
                      contents,
                    ],
                  ),
                );
              }
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: viewport.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SlowlightSpacing.page,
                      vertical: SlowlightSpacing.page,
                    ),
                    child: splitDesktop
                        ? Center(child: content)
                        : Align(
                            alignment: Alignment.topCenter,
                            child: content,
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
