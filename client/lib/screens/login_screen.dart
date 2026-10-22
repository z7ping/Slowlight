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

enum _LoginView { welcome, github, password, register, local }

class LoginScreen extends StatefulWidget {
  /// Auth-only mode for data migration: never switch the active data source.
  final bool preserveDataMode;

  const LoginScreen({super.key, this.preserveDataMode = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _nicknameController = TextEditingController();
  _LoginView _view = _LoginView.welcome;
  bool _allowCompletionPop = false;
  bool get _isLogin => _view != _LoginView.register;

  void _open(_LoginView next) {
    if (_isLoading) return;
    setState(() => _view = next);
  }
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
      if (!widget.preserveDataMode) {
        await DataModeManager().setCloud();
        authStateNotifier.value = !authStateNotifier.value;
      }
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
      _view = _LoginView.github;
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
      if (!widget.preserveDataMode) {
        await DataModeManager().setCloud();
      }
      if (!isCurrent()) return;
      if (!widget.preserveDataMode) {
        authStateNotifier.value = !authStateNotifier.value;
      }
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
          _githubFinishing = false;
        });
      }
    }
  }

  Future<void> _stopGitHubWaiting() async {
    if (_githubFinishing) return;
    final attempt = ++_githubAttempt;
    setState(() {
      _githubAuthorizing = false;
      _githubFinishing = false;
      _view = _LoginView.welcome;
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
      if (!widget.preserveDataMode) {
        await DataModeManager().setLocal();
        await AuthService.initLocalUser();
        authStateNotifier.value = !authStateNotifier.value;
      }
      if (mounted) _finish(false);
    } catch (e) {
      if (mounted) FxNotice.errorWithDetails(context, '进入本地数据失败', e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _finish(bool value, {String? successMessage}) {
    // 授权中 PopScope 禁止返回；只有真实登录/本地模式成功后放行导航。
    // 下一帧执行，保证 PopScope 先更新，且提示不依赖即将销毁的页面。
    final notice = successMessage == null ? null : FxNotice.capture(context);
    setState(() => _allowCompletionPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
          description: widget.preserveDataMode
              ? '云端身份已验证，仍使用本机数据。'
              : value ? '已进入云端模式，可在侧边栏查看同步状态' : '当前数据保存在本机',
          variant: FxNoticeVariant.success,
          duration: const Duration(seconds: 4),
        );
      }
    });
  }

  void _message(String text) {
    FxNotice.showContent(context, Text(text));
  }


  Widget _backButton() => Align(
        alignment: Alignment.centerLeft,
        child: FxButton(
          key: const ValueKey('login.back'),
          label: '返回',
          icon: Icons.arrow_back_rounded,
          variant: FxButtonVariant.ghost,
          size: FxButtonSize.sm,
          onPressed: _isLoading ? null : () => _open(_LoginView.welcome),
        ),
      );

  Widget _brand(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const ValueKey('login.brand'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SlowlightLogo(size: 44),
        const SizedBox(width: SlowlightSpacing.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(kBrandDisplayName,
                  style: SlowlightTypography.cardTitle(context).copyWith(
                    fontWeight: FontWeight.w700,
                  )),
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

  Widget _home(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('login.page_welcome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _brand(context),
        const SizedBox(height: SlowlightSpacing.page * 2),
        Text('欢迎回来', style: SlowlightTypography.hero(context)),
        const SizedBox(height: SlowlightSpacing.md),
        Text('选择一种方式开始，让每段记录都有迹可循。',
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        const SizedBox(height: SlowlightSpacing.page),
        if (_githubError != null) ...[
          Text(_githubError!,
              key: const ValueKey('login.github_error'),
              style: SlowlightTypography.caption(context).copyWith(
                color: theme.colorScheme.error,
              )),
          const SizedBox(height: SlowlightSpacing.md),
        ],
        SizedBox(
          width: double.infinity,
          child: FxButton(
            key: const ValueKey('login.github_action'),
            label: _githubError == null ? '使用 GitHub 继续' : '继续 GitHub 授权',
            icon: LucideIcons.gitFork,
            size: FxButtonSize.lg,
            expanded: true,
            onPressed: _isLoading
                ? null
                : () => _loginWithGitHub(
                    resumePending: _githubError != null && _githubCanResume),
          ),
        ),
        if (_deviceFlowEnabled) ...[
          const SizedBox(height: SlowlightSpacing.xs),
          Align(
            alignment: Alignment.center,
            child: FxButton(
              key: const ValueKey('login.github_device_action'),
              label: '验证码登录（备用）',
              size: FxButtonSize.sm,
              variant: FxButtonVariant.link,
              onPressed: _isLoading
                  ? null
                  : () => _loginWithGitHub(useDeviceCode: true),
            ),
          ),
        ],
        const SizedBox(height: SlowlightSpacing.xl),
        FxButton(
          key: const ValueKey('login.password_action'),
          label: '使用账号密码登录',
          icon: LucideIcons.userRound,
          variant: FxButtonVariant.outline,
          size: FxButtonSize.lg,
          expanded: true,
          onPressed: _isLoading ? null : () => _open(_LoginView.password),
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('还没有账号？',
                style: SlowlightTypography.caption(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            FxButton(
              key: const ValueKey('login.switch_mode'),
              label: '创建账号',
              variant: FxButtonVariant.link,
              size: FxButtonSize.sm,
              onPressed: _isLoading ? null : () => _open(_LoginView.register),
            ),
          ],
        ),
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
          onPressed: _isLoading ? null : () => _open(_LoginView.local),
        ),
        const SizedBox(height: SlowlightSpacing.xs),
        Text('无需账号，记录仅保存在当前设备',
            textAlign: TextAlign.center,
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }

  Widget _oauth(BuildContext context) {
    final theme = Theme.of(context);
    final isWaiting = _githubAuthorizing;
    return Column(
      key: const ValueKey('login.page_github'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_githubFinishing)
          _githubAuthorizing
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: FxButton(
                    key: const ValueKey('login.back'),
                    label: '返回',
                    icon: Icons.arrow_back_rounded,
                    size: FxButtonSize.sm,
                    variant: FxButtonVariant.ghost,
                    onPressed: _stopGitHubWaiting,
                  ),
                )
              : _backButton(),
        const SizedBox(height: SlowlightSpacing.xxxl),
        Center(
          child: Icon(LucideIcons.gitFork,
              size: SlowlightIconSize.heroGlyph,
              color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: SlowlightSpacing.xxxl),
        Text(isWaiting ? '等待 GitHub 授权' : 'GitHub 授权未完成',
            style: SlowlightTypography.hero(context),
            textAlign: TextAlign.center),
        const SizedBox(height: SlowlightSpacing.md),
        Text(
          isWaiting
              ? '请在浏览器完成授权，客户端会自动检查登录结果。'
              : '你可以继续检查上次授权，或重新发起登录。',
          textAlign: TextAlign.center,
          style: SlowlightTypography.secondary(context).copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.page),
        FxCard(
          padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
          color: fxSubtleSurface(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _oauthStep(context,
                  label: '已发起授权',
                  icon: Icons.check_circle_outline_rounded,
                  active: isWaiting),
              const SizedBox(height: SlowlightSpacing.xxxl),
              _oauthStep(context,
                  label: isWaiting ? _githubStatus : '等待授权结果',
                  icon: Icons.sync_rounded,
                  active: isWaiting,
                  loading: isWaiting),
              const SizedBox(height: SlowlightSpacing.xxxl),
              _oauthStep(context,
                  label: '完成登录',
                  icon: Icons.circle_outlined,
                  active: false),
            ],
          ),
        ),
        if (_githubDeviceCode != null &&
            _githubVerificationUri != null) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          SelectableText(
            _githubDeviceCode!,
            key: const ValueKey('login.github_device_code'),
            style: SlowlightTypography.sectionTitle(context),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SlowlightSpacing.md),
          FxButton(
            key: const ValueKey('login.github_device_copy'),
            label: '复制验证码',
            variant: FxButtonVariant.outline,
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: _githubDeviceCode!));
              if (mounted) _message('验证码已复制');
            },
          ),
          const SizedBox(height: SlowlightSpacing.md),
          FxButton(
            key: const ValueKey('login.github_device_open'),
            label: '打开 GitHub 验证页面',
            variant: FxButtonVariant.outline,
            expanded: true,
            onPressed: () async {
              final uri = _githubVerificationUri;
              if (uri != null &&
                  !await launchUrl(uri,
                      mode: LaunchMode.externalApplication) &&
                  mounted) {
                _message('无法打开 GitHub，请手动访问 github.com/login/device');
              }
            },
          ),
        ],
        if (_githubError != null) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          Text(_githubError!,
              key: const ValueKey('login.github_error'),
              style: SlowlightTypography.secondary(context).copyWith(
                color: theme.colorScheme.error,
              )),
        ],
        const SizedBox(height: SlowlightSpacing.page),
        if (isWaiting) ...[
          if (theme.platform == TargetPlatform.windows ||
              theme.platform == TargetPlatform.android)
            FxButton(
              key: const ValueKey('login.github_check'),
              label: '检查授权结果',
              icon: Icons.refresh_rounded,
              expanded: true,
              onPressed: () {
                if (!GitHubSignIn.checkAuthorizationNow()) {
                  _message('授权会话正在初始化，请稍后重试');
                }
              },
            ),
          if (_githubDeviceCode == null) ...[
            const SizedBox(height: SlowlightSpacing.md),
            FxButton(
              key: const ValueKey('login.github_reopen'),
              label: '返回 GitHub 授权页',
              variant: FxButtonVariant.outline,
              expanded: true,
              onPressed: () async {
                try {
                  if (!await GitHubSignIn.reopenAuthorization() && mounted) {
                    _message('无法打开授权页，请取消等待后重新授权');
                  }
                } catch (_) {
                  if (mounted) _message('无法打开浏览器，请检查默认浏览器设置');
                }
              },
            ),
          ],
          const SizedBox(height: SlowlightSpacing.md),
          FxButton(
            key: const ValueKey('login.github_cancel'),
            label: '取消授权等待',
            variant: FxButtonVariant.link,
            expanded: true,
            onPressed: _githubFinishing ? null : _stopGitHubWaiting,
          ),
        ] else ...[
          FxButton(
            key: const ValueKey('login.github_retry'),
            label: _githubCanResume ? '继续检查上次授权' : '重新授权',
            expanded: true,
            onPressed: _isLoading
                ? null
                : () => _loginWithGitHub(resumePending: _githubCanResume),
          ),
        ],
        const SizedBox(height: SlowlightSpacing.md),
        Text('只有客户端完成确认后才算登录成功。',
            textAlign: TextAlign.center,
            style: SlowlightTypography.caption(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }

  Widget _oauthStep(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool active,
    bool loading = false,
  }) {
    final foreground = active
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        if (loading)
          FxCircularProgress(
            constraints: const BoxConstraints.tightFor(width: 19, height: 19),
            strokeWidth: 2,
            semanticsLabel: '正在检查授权',
          )
        else
          Icon(icon, size: SlowlightIconSize.md, color: foreground),
        const SizedBox(width: SlowlightSpacing.xl),
        Expanded(
          child: Text(label,
              style: SlowlightTypography.secondary(context).copyWith(
                color: foreground,
              )),
        ),
      ],
    );
  }

  Widget _credentials(BuildContext context) {
    final theme = Theme.of(context);
    final register = !_isLogin;
    return Column(
      key: ValueKey(register ? 'login.page_register' : 'login.page_password'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backButton(),
        const SizedBox(height: SlowlightSpacing.page),
        Text(register ? '创建云端账号' : '账号密码登录',
            style: SlowlightTypography.hero(context)),
        const SizedBox(height: SlowlightSpacing.md),
        Text(register
                ? '创建账号，在不同设备查看自己的记录。'
                : '登录后，在不同设备间延续记录。',
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        const SizedBox(height: SlowlightSpacing.page),
        FxInput(
          controller: _usernameController,
          enabled: !_isLoading,
          textInputAction: TextInputAction.next,
          label: '账号',
          placeholder: register ? '设置用户名' : '邮箱或用户名',
        ),
        if (register) ...[
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
          textInputAction: register
              ? TextInputAction.next
              : TextInputAction.done,
          onSubmitted: register ? null : (_) => _submit(),
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
        if (register) ...[
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
          child: FxButton(
            label: _isLoading
                ? '处理中…'
                : register
                    ? '创建账号'
                    : '登录',
            expanded: true,
            size: FxButtonSize.lg,
            onPressed: _isLoading ? null : _submit,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(register ? '已经有账号？' : '还没有账号？',
                style: SlowlightTypography.caption(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            FxButton(
              key: const ValueKey('login.switch_mode'),
              label: register ? '返回登录' : '创建账号',
              variant: FxButtonVariant.link,
              size: FxButtonSize.sm,
              onPressed: _isLoading
                  ? null
                  : () => _open(register
                      ? _LoginView.password
                      : _LoginView.register),
            ),
          ],
        ),
        const SizedBox(height: SlowlightSpacing.page),
        FxSeparator.horizontal(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: SlowlightSpacing.md),
        FxButton(
          key: const ValueKey('login.github_from_password'),
          label: '使用 GitHub 继续',
          icon: LucideIcons.gitFork,
          variant: FxButtonVariant.ghost,
          expanded: true,
          onPressed: _isLoading ? null : () => _loginWithGitHub(),
        ),
      ],
    );
  }

  Widget _localIntro(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('login.page_local'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _backButton(),
        const SizedBox(height: SlowlightSpacing.page),
        Align(
          child: Icon(LucideIcons.smartphone,
              size: SlowlightIconSize.heroGlyph,
              color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: SlowlightSpacing.xxxl),
        Text('无需登录，直接开始',
            style: SlowlightTypography.hero(context),
            textAlign: TextAlign.center),
        const SizedBox(height: SlowlightSpacing.md),
        Text('所有记录保存在当前设备，不会自动上传或合并到云端。',
            textAlign: TextAlign.center,
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        const SizedBox(height: SlowlightSpacing.page),
        FxCard(
          padding: const EdgeInsets.all(SlowlightSpacing.xxxl),
          color: fxSubtleSurface(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _localFact(context, '使用任务、习惯与回顾'),
              const SizedBox(height: SlowlightSpacing.xl),
              _localFact(context, '不需要网络或云端账号'),
              const SizedBox(height: SlowlightSpacing.xl),
              _localFact(context, '迁移云端需要主动预览并确认'),
            ],
          ),
        ),
        const SizedBox(height: SlowlightSpacing.page),
        FxButton(
          key: const ValueKey('login.local_confirm'),
          label: _isLoading ? '正在准备本地数据…' : '开始使用本地数据',
          expanded: true,
          size: FxButtonSize.lg,
          onPressed: _isLoading ? null : _useLocal,
        ),
        const SizedBox(height: SlowlightSpacing.md),
        FxButton(
          key: const ValueKey('login.local_cancel'),
          label: '返回登录',
          variant: FxButtonVariant.ghost,
          expanded: true,
          onPressed: _isLoading ? null : () => _open(_LoginView.welcome),
        ),
      ],
    );
  }

  Widget _localFact(BuildContext context, String label) => Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: SlowlightIconSize.md,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: SlowlightSpacing.xl),
          Expanded(
            child: Text(label,
                style: SlowlightTypography.secondary(context)),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowCompletionPop ||
          (_view == _LoginView.welcome && !_githubAuthorizing),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _allowCompletionPop) return;
        if (_view == _LoginView.github && _githubAuthorizing) {
          if (!_githubFinishing) unawaited(_stopGitHubWaiting());
        } else if (!_isLoading) {
          _open(_LoginView.welcome);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final isDesktop =
                  !SlowlightPlatformDensity.usesMobileTouchTargets &&
                  viewport.maxWidth >= SlowlightBreakpoints.tabletMin;
              final content = switch (_view) {
                _LoginView.welcome => _home(context),
                _LoginView.github => _oauth(context),
                _LoginView.password || _LoginView.register =>
                  _credentials(context),
                _LoginView.local => _localIntro(context),
              };
              final panel = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 510),
                child: isDesktop
                    ? FxCard(
                        padding: const EdgeInsets.all(SlowlightSpacing.page),
                        borderRadius: SlowlightRadius.xl,
                        child: content,
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SlowlightSpacing.page,
                        ),
                        child: content,
                      ),
              );
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? SlowlightSpacing.page : 0,
                      vertical: SlowlightSpacing.page,
                    ),
                    child: isDesktop
                        ? Center(child: panel)
                        : Align(
                            alignment: Alignment.topCenter,
                            child: panel,
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
