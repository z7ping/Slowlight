import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../brand.dart';
import '../main.dart' show authStateNotifier;
import '../services/auth_service.dart';
import '../services/data_mode_manager.dart';
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
  bool _obscurePassword = true;

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
      await DataModeManager().setCloud();
      authStateNotifier.value = !authStateNotifier.value;
      if (mounted) _finish(true);
    } catch (e) {
      if (mounted) _message(_isLogin ? '登录失败：$e' : '注册失败：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _useLocal() async {
    setState(() => _isLoading = true);
    try {
      await DataModeManager().setLocal();
      await AuthService.initLocalUser();
      authStateNotifier.value = !authStateNotifier.value;
      if (mounted) _finish(false);
    } catch (e) {
      if (mounted) _message('进入本地数据失败：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _finish(bool value) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(value);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  void _message(String text) {
    FxNotice.showContent(context, Text(text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SlowlightLogo(size: 52),
                  const SizedBox(height: 14),
                  Text(
                    kBrandDisplayName,
                    textAlign: TextAlign.center,
                    style: SlowlightTypography.pageTitle(context),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录云端，跨设备保存你的记录；也可选择本地独立使用',
                    textAlign: TextAlign.center,
                    style: SlowlightTypography.secondary(
                      context,
                    ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 22),
                  FxInput(
                    controller: _usernameController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    placeholder: _isLogin ? '邮箱或用户名' : '用户名',
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 8),
                    FxInput(
                      controller: _emailController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      placeholder: '邮箱',
                    ),
                  ],
                  const SizedBox(height: 8),
                  FxInput(
                    controller: _passwordController,
                    enabled: !_isLoading,
                    obscureText: _obscurePassword,
                    textInputAction:
                        _isLogin ? TextInputAction.done : TextInputAction.next,
                    onSubmitted: _isLogin ? (_) => _submit() : null,
                    placeholder: '密码',
                    trailing: FxIconButton(
                      tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                      onPressed:
                          () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                      icon:
                          _obscurePassword
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff,
                      iconSize: 17,
                    ),
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 8),
                    FxInput(
                      controller: _nicknameController,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      placeholder: '昵称（可选）',
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    key: const ValueKey('login.primary_action'),
                    width: double.infinity,
                    height: SlowlightPlatformDensity.usesMobileTouchTargets ? 52 : 44,
                    child: FxButton(
                      label: _isLoading ? '处理中…' : _isLogin ? '登录' : '创建账号',
                      size: FxButtonSize.lg,
                      expanded: true,
                      onPressed: _isLoading ? null : _submit,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FxSeparator.horizontal(
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 12),
                  FxButton(
                    label: '仅使用本地数据（不与云端自动同步）',
                    icon: LucideIcons.smartphone,
                    variant: FxButtonVariant.link,
                    expanded: true,
                    onPressed: _isLoading ? null : _useLocal,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text(
                        _isLogin ? '还没有账号？' : '已有账号？',
                        style: SlowlightTypography.caption(
                          context,
                        ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      FxButton(
                        label: _isLogin ? '注册' : '登录',
                        variant: FxButtonVariant.link,
                        size: FxButtonSize.sm,
                        onPressed:
                            _isLoading
                                ? null
                                : () => setState(() => _isLogin = !_isLogin),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
