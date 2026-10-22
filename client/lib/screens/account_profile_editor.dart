import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/github_sign_in.dart';
import '../ui/fx.dart';

/// 编辑弹窗只返回是否已保存；身份与资料刷新由账号页统一处理。
Future<bool> editCloudNickname(BuildContext context, User user) async {
  final done = await FxDialog.show<bool>(
    context: context,
    title: '修改昵称',
    width: 400,
    child: _NicknameForm(initialName: user.nickname),
  );
  return done == true;
}

Future<bool> manageAccountPassword(BuildContext context, {
  required bool alreadySet,
  required String username,
}) async {
  final done = await FxDialog.show<bool>(
    context: context,
    title: alreadySet ? '修改登录密码' : '设置账号密码',
    width: 430,
    barrierDismissible: false,
    child: _PasswordForm(alreadySet: alreadySet, username: username),
  );
  return done == true;
}

class _NicknameForm extends StatefulWidget {
  const _NicknameForm({required this.initialName});
  final String initialName;

  @override
  State<_NicknameForm> createState() => _NicknameFormState();
}

class _NicknameFormState extends State<_NicknameForm> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _name.text.trim();
    if (value.isEmpty || value.runes.length > 50) {
      FxNotice.error(context, '昵称应为 1–50 个字符');
      return;
    }
    setState(() => _saving = true);
    try {
      await AuthService.updateNickname(value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) FxNotice.errorWithDetails(context, '保存昵称失败', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FxInput(
        key: const ValueKey('account.nickname.input'),
        controller: _name,
        label: '昵称',
        maxLength: 50,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) { if (!_saving) _save(); },
        enabled: !_saving,
      ),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        FxButton(label: '取消', variant: FxButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false)),
        const SizedBox(width: 8),
        FxButton(key: const ValueKey('account.nickname.save'),
          label: _saving ? '保存中…' : '保存',
          onPressed: _saving ? null : _save),
      ]),
    ],
  );
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.alreadySet, required this.username});
  final bool alreadySet;
  final String username;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _username = TextEditingController();
  final _old = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _username.dispose();
    _old.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _password.text;
    if (!widget.alreadySet &&
        (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{2,29}$').hasMatch(_username.text.trim()) ||
            _username.text.trim().toLowerCase().startsWith('github_'))) {
      FxNotice.error(context, '账号须为 3–30 位字母、数字或下划线，且以字母开头');
      return;
    }
    final byteLength = utf8.encode(password).length;
    if (byteLength < 10 || byteLength > 72 || password != _confirm.text) {
      FxNotice.error(context, '密码须为 10–72 字节，且两次输入一致');
      return;
    }
    if (widget.alreadySet && _old.text.isEmpty) {
      FxNotice.error(context, '请填写当前密码');
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.alreadySet) {
        await AuthService.changePassword(
          currentPassword: _old.text,
          newPassword: password,
        );
      } else {
        // 再次核对 GitHub 身份；不能只凭一个旧的已登录 JWT 认领密码。
        final verified = await GitHubSignIn.signIn(
          linkExisting: true,
          shouldContinue: () => mounted && _saving,
        );
        if (!verified || !mounted) return;
        await AuthService.setupPassword(
          username: _username.text.trim(),
          password: password,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) FxNotice.errorWithDetails(context, '账号密码操作失败', e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.alreadySet) ...[
        const Text('设置后可以使用 GitHub 或账号密码登录同一个 Slowlight 账号。保存前需要重新验证 GitHub 身份。'),
        const SizedBox(height: 12),
        FxInput(key: const ValueKey('account.password.username'),
          label: '登录账号', placeholder: '3–30 位字母、数字、下划线',
          controller: _username, enabled: !_saving),
      ] else ...[
        Text('登录账号：${widget.username}'),
        const SizedBox(height: 12),
        FxInput(label: '当前密码', controller: _old,
          obscureText: true, enabled: !_saving),
      ],
      const SizedBox(height: 12),
      FxInput(key: const ValueKey('account.password.new'),
        label: widget.alreadySet ? '新密码' : '登录密码',
        controller: _password, obscureText: true, enabled: !_saving),
      const SizedBox(height: 12),
      FxInput(label: '确认密码', controller: _confirm, obscureText: true, enabled: !_saving),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        FxButton(label: '取消', variant: FxButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false)),
        const SizedBox(width: 8),
        FxButton(key: const ValueKey('account.password.save'),
          label: _saving ? '处理中…' : widget.alreadySet ? '修改密码' : '验证并设置',
          onPressed: _saving ? null : _save),
      ]),
    ],
  );
}
