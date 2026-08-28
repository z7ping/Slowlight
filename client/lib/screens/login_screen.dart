import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../brand.dart';
import '../main.dart' show authStateNotifier;
import '../services/auth_service.dart';
import '../services/data_mode_manager.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../ui/widgets/slowlight_logo.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';
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
          nickname: _nicknameController.text.trim().isEmpty
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
    );
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
                children: [
                  const SlowlightLogo(size: 52),
                  const SizedBox(height: 14),
                  const Text(
                    kBrandDisplayName,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '了解自己的系统 · 数据位置由你选择',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FxButton(
                    label: '使用本地数据（无需服务端）',
                    icon: LucideIcons.smartphone,
                    size: FxButtonSize.lg,
                    expanded: true,
                    onPressed: _isLoading ? null : _useLocal,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: Divider(color: hfBorder(context))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '或登录使用云端数据',
                          style: TextStyle(
                            fontSize: AppTheme.textXs,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: hfBorder(context))),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _usernameController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _isLogin ? '邮箱或用户名' : '用户名',
                    ),
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(hintText: '邮箱'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    enabled: !_isLoading,
                    obscureText: _obscurePassword,
                    textInputAction:
                        _isLogin ? TextInputAction.done : TextInputAction.next,
                    onSubmitted: _isLogin ? (_) => _submit() : null,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '密码',
                      suffixIcon: SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? LucideIcons.eye
                                : LucideIcons.eyeOff,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nicknameController,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(hintText: '昵称（可选）'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FxButton(
                    label: _isLoading
                        ? '处理中…'
                        : _isLogin
                            ? '登录'
                            : '注册',
                    expanded: true,
                    onPressed: _isLoading ? null : _submit,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLogin ? '还没有账号？' : '已有账号？',
                        style: TextStyle(
                          fontSize: AppTheme.textXs,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      FxButton(
                        label: _isLogin ? '注册' : '登录',
                        variant: FxButtonVariant.link,
                        size: FxButtonSize.sm,
                        onPressed: _isLoading
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
