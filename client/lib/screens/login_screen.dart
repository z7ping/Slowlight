import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../brand.dart';
import '../main.dart' show authStateNotifier;
import '../services/auth_service.dart';
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
  bool _isLoading = false;
  bool _githubAuthorizing = false;
  String _githubStatus = "等待 GitHub 完成授权…";
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
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
          nickname:
              _nicknameController.text.trim().isEmpty
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

  Future<void> _loginWithGitHub({bool resumePending = false}) async {
    setState(() {
      _isLoading = true;
      _githubAuthorizing = true;
      _githubStatus = resumePending
          ? '正在恢复上次 GitHub 授权…'
          : '等待 GitHub 完成授权…';
    });
    try {
      final completed = await GitHubSignIn.signIn(
        shouldContinue: () => mounted && _githubAuthorizing,
        resumePending: resumePending,
        onStatus: (status) {
          if (mounted && _githubAuthorizing) {
            setState(() => _githubStatus = status);
          }
        },
      );
      if (!mounted || !completed) return;
      await DataModeManager().setCloud();
      authStateNotifier.value = !authStateNotifier.value;
      if (mounted) _finish(true, successMessage: 'GitHub 登录成功');
    } catch (e) {
      if (mounted) {
        final message = GitHubSignIn.describeError(e);
        if (GitHubSignIn.isTransientNetworkFailure(e)) {
          FxNotice.error(
            context,
            '云端连接失败',
            description: message,
            duration: const Duration(seconds: 12),
            action: FxNoticeAction(
              label: '重新尝试',
              onPressed: () {
                if (mounted && !_isLoading) _loginWithGitHub();
              },
            ),
          );
        } else {
          FxNotice.errorWithDetails(context, 'GitHub 登录失败', message);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _githubAuthorizing = false;
        });
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
        description: value
            ? '已进入云端模式，可在侧边栏查看同步状态'
            : '当前数据保存在本机',
        variant: FxNoticeVariant.success,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void _message(String text) {
    FxNotice.showContent(context, Text(text));
  }

  Widget _buildLoginContents(BuildContext context, {required bool compactHeight}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SlowlightLogo(size: compactHeight ? 60 : 72),
              const SizedBox(height: SlowlightSpacing.xxxl),
              Text(
                kBrandDisplayName,
                style: SlowlightTypography.hero(context).copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SlowlightSpacing.xs),
              Text(
                kBrandTagline,
                textAlign: TextAlign.center,
                style: SlowlightTypography.secondary(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compactHeight ? SlowlightSpacing.page : 40),
        Text(
          _isLogin ? '欢迎回来' : '创建云端账号',
          style: SlowlightTypography.hero(context).copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Text(
          _isLogin
              ? '登录后，让每一段记录在设备间延续。'
              : '用一个账号，保存值得回看的日常。',
          style: SlowlightTypography.secondary(context).copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Text(
          '只想先在这台设备上记录？页面下方可以不登录直接开始。',
          style: SlowlightTypography.caption(context).copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.page),
        FxButton(
          key: const ValueKey('login.github_action'),
          label: '使用 GitHub 继续',
          icon: LucideIcons.gitFork,
          expanded: true,
          size: FxButtonSize.lg,
          variant: FxButtonVariant.outline,
          onPressed: _isLoading ? null : _loginWithGitHub,
        ),
        if (_githubAuthorizing) ...[
          const SizedBox(height: SlowlightSpacing.md),
          Text(
            _githubStatus,
            textAlign: TextAlign.center,
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SlowlightSpacing.md),
          if (Theme.of(context).platform == TargetPlatform.windows ||
              Theme.of(context).platform == TargetPlatform.android) ...[
            const SizedBox(height: SlowlightSpacing.md),
            FxButton(
              key: const ValueKey('login.github_check'),
              label: '检查授权结果',
              variant: FxButtonVariant.outline,
              onPressed: () {
                if (!GitHubSignIn.checkAuthorizationNow()) {
                  _message('授权会话正在初始化，请稍后重试');
                }
              },
            ),
            const SizedBox(height: SlowlightSpacing.xs),
            Text(
              '浏览器授权成功后会自动检查；'
              '如果返回应用后仍在等待，可手动检查。',
              textAlign: TextAlign.center,
              style: SlowlightTypography.caption(context).copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          FxButton(
            key: const ValueKey('login.github_cancel'),
            label: '取消授权等待',
            variant: FxButtonVariant.link,
            onPressed: () async {
              setState(() => _githubAuthorizing = false);
              try {
                await GitHubSignIn.cancelPendingAuthorization();
              } catch (_) {
                // 取消当前等待立即生效，不依赖系统存储是否可用。
              }
            },
          ),
        ],
        const SizedBox(height: SlowlightSpacing.xl),
        Center(
          child: Text(
            _isLogin ? '或使用账号密码' : '或创建普通账号',
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: SlowlightSpacing.xl),
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
            icon:
                _obscurePassword
                    ? LucideIcons.eye
                    : LucideIcons.eyeOff,
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
        const SizedBox(height: SlowlightSpacing.page),
        ConstrainedBox(
          key: const ValueKey('login.primary_action'),
          constraints: BoxConstraints(
            minHeight: SlowlightPlatformDensity.usesMobileTouchTargets
                ? 52
                : SlowlightControlSize.minTouchTarget,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FxButton(
              label: _isLoading ? '处理中…' : _isLogin ? '登录' : '创建账号',
              size: FxButtonSize.lg,
              expanded: true,
              onPressed: _isLoading ? null : _submit,
            ),
          ),
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _isLogin ? '还没有账号？' : '已有账号？',
                style: SlowlightTypography.secondary(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            FxButton(
              key: const ValueKey('login.switch_mode'),
              label: _isLogin ? '注册' : '返回登录',
              variant: FxButtonVariant.link,
              size: FxButtonSize.sm,
              onPressed: _isLoading
                  ? null
                  : () => setState(() => _isLogin = !_isLogin),
            ),
          ],
        ),
        const SizedBox(height: SlowlightSpacing.page),
        FxSeparator.horizontal(
          color: theme.colorScheme.outlineVariant,
        ),
        const SizedBox(height: SlowlightSpacing.xl),
        Center(
          child: FxButton(
            key: const ValueKey('login.local_action'),
            label: '不登录，使用本地数据',
            icon: LucideIcons.smartphone,
            variant: FxButtonVariant.ghost,
            size: FxButtonSize.lg,
            onPressed: _isLoading ? null : _useLocal,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.xs),
        Text(
          '本机记录不会自动上传或合并。将来可在设置中选择云端数据，迁移需要主动预览并确认。',
          textAlign: TextAlign.center,
          style: SlowlightTypography.caption(context).copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final desktop = viewport.maxWidth >= SlowlightBreakpoints.tabletMin;
            final compactHeight = desktop || viewport.maxHeight < 640;
            final contents = _buildLoginContents(
              context,
              compactHeight: compactHeight,
            );
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: SlowlightSpacing.page,
                      vertical: compactHeight
                          ? SlowlightSpacing.xxxl
                          : SlowlightSpacing.page,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 448),
                      child: desktop
                          ? FxCard(
                              padding: const EdgeInsets.all(
                                SlowlightSpacing.page,
                              ),
                              borderRadius: SlowlightRadius.xl,
                              child: contents,
                            )
                          : contents,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
