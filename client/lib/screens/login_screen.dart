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
    if (_isLoading || (widget.preserveDataMode && next == _LoginView.local)) return;
    setState(() {
      _view = next;
      // Leaving the form deliberately abandons the mode-switch recovery UI.
      _credentialsSavedForCloud = false;
      _credentialsCloudError = null;
    });
  }
  bool _isLoading = false;
  bool _credentialsSavedForCloud = false;
  String? _credentialsCloudError;
  bool _githubAuthorizing = false;
  bool _githubFinishing = false;
  int _githubAttempt = 0;
  String? _githubError;
  bool _githubCanResume = false;
  bool _githubCancelFailed = false;
  // Saved credentials must not be re-authorized when only the mode switch fails.
  bool _githubCredentialsSaved = false;
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
    if (_isLoading) return;
    if (_credentialsSavedForCloud) {
      await _retryStoredCredentialsCloudMode();
      return;
    }
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final email = _emailController.text.trim();
    if (username.isEmpty || password.trim().isEmpty) {
      _message('请填写完整信息');
      return;
    }
    if (!_isLogin) {
      // Mirror the existing /auth/register required/min/max constraints.
      // Server validation remains the final authority for email addresses.
      if (username.runes.length < 3 || username.runes.length > 50) {
        _message('账号需为 3–50 个字符');
        return;
      }
      if (email.isEmpty) {
        _message('请填写邮箱');
        return;
      }
      if (email.contains(RegExp(r'\s')) ||
          email.split('@').length != 2 ||
          email.startsWith('@') ||
          email.endsWith('@')) {
        _message('请输入有效的邮箱地址');
        return;
      }
      if (password.runes.length < 6) {
        _message('密码至少需要 6 个字符');
        return;
      }
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
        try {
          await DataModeManager().setCloud();
        } catch (error) {
          unawaited(AppErrorLogger.instance.write(
              source: 'password_cloud_mode', error: error));
          if (mounted) {
            setState(() {
              _credentialsSavedForCloud = true;
              _credentialsCloudError = '云端身份已保存，但切换数据模式失败。'
                  '请重试进入云端，不需要重新提交账号信息。\\n$error';
            });
          }
          return;
        }
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
        // Registration may already have committed remotely when the response
        // or local credential persistence fails. Do not invite a blind retry.
        FxNotice.errorWithDetails(
          context,
          _isLogin ? '登录失败' : '注册结果待核对',
          _isLogin
              ? e.toString()
              : '若请求已送达云端，账号可能已经创建。请先尝试登录核对，避免重复注册。\n$e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _retryStoredCredentialsCloudMode() async {
    if (_isLoading || !_credentialsSavedForCloud) return;
    setState(() {
      _isLoading = true;
      _credentialsCloudError = null;
    });
    try {
      if (!await AuthService.isLoggedIn()) {
        if (mounted) {
          setState(() {
            // Registration may have already succeeded. Never offer to submit
            // the registration again just because the saved JWT expired.
            _credentialsSavedForCloud = false;
            _view = _LoginView.password;
            _credentialsCloudError = '已保存身份失效，请使用账号密码登录核对。';
          });
        }
        return;
      }
      await DataModeManager().setCloud();
      if (!mounted) return;
      authStateNotifier.value = !authStateNotifier.value;
      _finish(
        true,
        successMessage: _isLogin ? '登录成功' : '账号创建成功',
      );
    } catch (error) {
      unawaited(AppErrorLogger.instance.write(
          source: 'password_cloud_mode_retry', error: error));
      if (mounted) {
        setState(() {
          _credentialsCloudError =
              '云端身份已保存，数据模式仍未切换。请重试进入云端。\\n$error';
        });
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
      _githubCancelFailed = false;
      _githubCredentialsSaved = false;
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
      if (!isCurrent()) return;
      if (!completed) {
        setState(() {
          _githubError = '上次 GitHub 授权已失效，请重新授权。';
          _githubCanResume = false;
        });
        return;
      }
      if (widget.preserveDataMode) {
        _finish(true, successMessage: 'GitHub 登录成功');
        return;
      }
      // signIn only returns true after the JWT has been safely persisted.
      setState(() {
        _githubCredentialsSaved = true;
        _githubDeviceCode = null;
        _githubVerificationUri = null;
      });
      await _enterCloudAfterGitHub(isCurrent);
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

  Future<void> _enterCloudAfterGitHub(bool Function() isCurrent) async {
    try {
      await DataModeManager().setCloud();
    } catch (error) {
      unawaited(AppErrorLogger.instance.write(
          source: 'github_cloud_mode', error: error));
      if (isCurrent()) {
        setState(() {
          _githubError = 'GitHub 登录凭据已保存，但切换云端数据失败。'
              '请重试进入云端，不需要重复授权。\n$error';
          _githubCanResume = false;
        });
      }
      return;
    }
    if (!isCurrent()) return;
    authStateNotifier.value = !authStateNotifier.value;
    _finish(true, successMessage: 'GitHub 登录成功');
  }

  Future<void> _retryGitHubCloudMode() async {
    if (_isLoading || !_githubCredentialsSaved) return;
    final attempt = ++_githubAttempt;
    bool isCurrent() => mounted && attempt == _githubAttempt;
    setState(() {
      _isLoading = true;
      _githubFinishing = true;
      _githubError = null;
    });
    try {
      // Never reuse an expired token, and never issue a second OAuth request.
      if (!await AuthService.isLoggedIn()) {
        if (isCurrent()) {
          setState(() {
            _githubCredentialsSaved = false;
            _githubError = '已保存的云端身份无效，请重新进行 GitHub 授权。';
          });
        }
        return;
      }
      if (isCurrent()) await _enterCloudAfterGitHub(isCurrent);
    } catch (error) {
      if (isCurrent()) {
        setState(() {
          _githubError = '读取已保存的云端身份失败，请重试。\n$error';
        });
      }
    } finally {
      if (isCurrent()) {
        setState(() {
          _isLoading = false;
          _githubFinishing = false;
        });
      }
    }
  }

  Future<void> _stopGitHubWaiting() async {
    if (_githubFinishing || _isLoading && !_githubAuthorizing) return;
    final attempt = ++_githubAttempt;
    setState(() {
      _githubAuthorizing = false;
      _githubFinishing = false;
      _isLoading = true;
    });
    try {
      await GitHubSignIn.cancelPendingAuthorization();
      if (mounted && attempt == _githubAttempt) {
        setState(() {
          _view = _LoginView.welcome;
          _githubError = null;
          _githubCanResume = false;
          _githubCancelFailed = false;
          _githubCredentialsSaved = false;
          _githubDeviceCode = null;
          _githubVerificationUri = null;
        });
      }
    } catch (error) {
      unawaited(
          AppErrorLogger.instance.write(source: 'github_cancel', error: error));
      if (mounted && attempt == _githubAttempt) {
        setState(() {
          _view = _LoginView.github;
          _githubError = '取消未完成：无法清除本机待恢复的授权，请重试取消。';
          _githubCancelFailed = true;
        });
      }
    } finally {
      if (mounted && attempt == _githubAttempt) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _useLocal() async {
    if (_isLoading || widget.preserveDataMode) return;
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
    // 授权中 PopScope 禁止返回；只有真实登录/本地模式成功后放行导航。
    // 下一帧执行，保证 PopScope 先更新，且提示不依赖即将销毁的页面。
    final notice = successMessage == null ? null : FxNotice.capture(context);
    setState(() => _allowCompletionPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      // Settings/migration opens LoginScreen as a route and expects a result.
      // The initial LoginScreen is AuthGate's child: the authStateNotifier
      // already triggers its rebuild. Never replace AuthGate's root route.
      if (navigator.canPop()) navigator.pop(value);
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
          onPressed: _isLoading
              ? null
              : () {
                  if (_view == _LoginView.github) {
                    _stopGitHubWaiting();
                  } else {
                    _open(_LoginView.welcome);
                  }
                },
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
        Text(widget.preserveDataMode ? '验证云端身份' : '欢迎回来',
            style: SlowlightTypography.hero(context)),
        const SizedBox(height: SlowlightSpacing.md),
        Text(widget.preserveDataMode
                ? '验证后继续迁移预览；当前仍使用本地数据。'
                : '选择一种方式开始，让每段记录都有迹可循。',
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
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
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
        if (!widget.preserveDataMode) ...[
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
        Text(
            isWaiting
                ? '等待 GitHub 授权'
                : _githubCredentialsSaved
                    ? 'GitHub 身份已验证'
                    : 'GitHub 授权未完成',
            style: SlowlightTypography.hero(context),
            textAlign: TextAlign.center),
        const SizedBox(height: SlowlightSpacing.md),
        Text(
          isWaiting
              ? (_githubDeviceCode == null
                  ? '请在浏览器完成授权，客户端会自动检查登录结果。'
                  : '请在 GitHub 验证页面输入下方验证码，客户端会自动检查结果。')
              : _githubCredentialsSaved
                  ? '登录凭据已安全保存，尚未切换到云端数据。重试不会再次请求授权。'
                  : _githubCanResume
                      ? '可以继续检查上次授权，或取消后重新登录。'
                      : '这次授权未完成，可以重新发起登录。',
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
                  active: isWaiting || _githubCredentialsSaved),
              const SizedBox(height: SlowlightSpacing.xxxl),
              _oauthStep(context,
                  label: _githubCredentialsSaved
                      ? '登录凭据已保存'
                      : isWaiting
                          ? _githubStatus
                          : '等待授权结果',
                  icon: _githubCredentialsSaved
                      ? Icons.check_circle_outline_rounded
                      : Icons.sync_rounded,
                  active: isWaiting || _githubCredentialsSaved,
                  loading: isWaiting),
              const SizedBox(height: SlowlightSpacing.xxxl),
              _oauthStep(context,
                  label: _githubCredentialsSaved ? '进入云端数据（待重试）' : '完成登录',
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
            label: _githubCredentialsSaved
                ? '重试进入云端'
                : _githubCanResume
                    ? '继续检查上次授权'
                    : '重新授权',
            expanded: true,
            onPressed: _isLoading || _githubCancelFailed
                ? null
                : _githubCredentialsSaved
                    ? _retryGitHubCloudMode
                    : () => _loginWithGitHub(resumePending: _githubCanResume),
          ),
          const SizedBox(height: SlowlightSpacing.md),
          FxButton(
            key: const ValueKey('login.github_cancel'),
            label: _githubCancelFailed
                ? '重试取消授权'
                : _githubCredentialsSaved
                    ? '返回欢迎页'
                    : '取消授权等待',
            variant: FxButtonVariant.link,
            expanded: true,
            onPressed: _isLoading ? null : _stopGitHubWaiting,
          ),
        ],
        const SizedBox(height: SlowlightSpacing.md),
        Text(_githubCredentialsSaved
                ? '云端身份已保存，但数据模式尚未切换。'
                : '只有客户端完成确认后才算登录成功。',
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
          enabled: !_isLoading && !_credentialsSavedForCloud,
          textInputAction: TextInputAction.next,
          label: '账号',
          placeholder: register ? '设置用户名' : '邮箱或用户名',
        ),
        if (register) ...[
          const SizedBox(height: SlowlightSpacing.xxxl),
          FxInput(
            controller: _emailController,
            enabled: !_isLoading && !_credentialsSavedForCloud,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            label: '邮箱',
            placeholder: '请输入邮箱',
          ),
        ],
        const SizedBox(height: SlowlightSpacing.xxxl),
        FxInput(
          controller: _passwordController,
          enabled: !_isLoading && !_credentialsSavedForCloud,
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
            onPressed: _isLoading || _credentialsSavedForCloud
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
            enabled: !_isLoading && !_credentialsSavedForCloud,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            label: '昵称（可选）',
            placeholder: '如何称呼你？',
          ),
        ],
        if (_credentialsCloudError != null) ...[
          const SizedBox(height: SlowlightSpacing.md),
          Text(
            _credentialsCloudError!,
            key: const ValueKey('login.credentials_cloud_error'),
            style: SlowlightTypography.secondary(context).copyWith(
              color: theme.colorScheme.error,
            ),
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
                : _credentialsSavedForCloud
                    ? '重试进入云端'
                    : register
                        ? '创建账号'
                        : '登录',
            expanded: true,
            size: FxButtonSize.lg,
            onPressed: _isLoading ? null : _submit,
          ),
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
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
        if (_view == _LoginView.github) {
          // System back must not skip clearing a pending GitHub login,
          // including after a failed authorization or failed cancellation.
          if (!_githubFinishing && (!_isLoading || _githubAuthorizing)) {
            unawaited(_stopGitHubWaiting());
          }
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
                _LoginView.local => widget.preserveDataMode
                    ? _home(context)
                    : _localIntro(context),
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
