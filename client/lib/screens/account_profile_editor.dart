import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/github_sign_in.dart';
import '../ui/fx.dart';

/// 编辑弹窗只返回是否已保存；身份与资料刷新由账号页统一处理。
/// Android 使用已有 FxSheet；Windows 继续沿用 FxDialog。
bool _accountMobile(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

Future<bool> editCloudNickname(BuildContext context, User user) async {
  if (_accountMobile(context)) {
    final formKey = GlobalKey<_NicknameFormState>();
    final done = await FxSheet.show<bool>(
      context: context,
      dismissible: false,
      draggable: false,
      showDragHandle: true,
      showCloseButton: false,
      onDismissRequested: () async => formKey.currentState?._cancel(),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('修改昵称', style: SlowlightTypography.cardTitle(sheetContext)),
            const SizedBox(height: 14),
            _NicknameForm(key: formKey, initialName: user.nickname),
          ],
        ),
      ),
    );
    return done == true;
  }
  final done = await FxDialog.show<bool>(
    context: context,
    title: '修改昵称',
    width: 400,
    barrierDismissible: false,
    showCloseButton: false,
    child: _NicknameForm(initialName: user.nickname),
  );
  return done == true;
}

Future<bool> manageAccountPassword(BuildContext context, {
  required bool alreadySet,
  required String username,
}) async {
  if (_accountMobile(context)) {
    final formKey = GlobalKey<_PasswordFormState>();
    final done = await FxSheet.show<bool>(
      context: context,
      dismissible: false,
      draggable: false,
      showDragHandle: true,
      showCloseButton: false,
      onDismissRequested: () async => formKey.currentState?._cancel(),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                alreadySet ? '修改登录密码' : '设置账号密码',
                style: SlowlightTypography.cardTitle(sheetContext),
              ),
              const SizedBox(height: 14),
              _PasswordForm(
                key: formKey,
                alreadySet: alreadySet,
                username: username,
              ),
            ],
          ),
        ),
      ),
    );
    return done == true;
  }
  final done = await FxDialog.show<bool>(
    context: context,
    title: alreadySet ? '修改登录密码' : '设置账号密码',
    width: 430,
    barrierDismissible: false,
    showCloseButton: false,
    child: _PasswordForm(alreadySet: alreadySet, username: username),
  );
  return done == true;
}

class _NicknameForm extends StatefulWidget {
  const _NicknameForm({super.key, required this.initialName});
  final String initialName;

  @override
  State<_NicknameForm> createState() => _NicknameFormState();
}

class _NicknameFormState extends State<_NicknameForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_saving) return;
    if (_name.text.trim() != widget.initialName.trim()) {
      final confirmed = await FxDialog.confirm(
        context: context,
        title: '放弃未保存的昵称？',
        content: '本次昵称修改尚未保存，离开后草稿将丢失。',
        cancelText: '继续编辑',
        confirmText: '放弃修改',
        destructive: true,
        draftDiscard: true,
      );
      if (confirmed != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    if (_saving) return;
    final value = _name.text.trim();
    if (value.isEmpty || value.runes.length > 50) {
      setState(() => _error = '昵称应为 1–50 个字符');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.updateNickname(value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      FxNotice.recordError('保存昵称失败', error);
      if (mounted) {
        setState(() => _error = FxNotice.readableError(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FxInput(
        key: const ValueKey('account.nickname.input'),
        controller: _name,
        label: '昵称',
        errorText: _error,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        maxLength: 50,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) { if (!_saving) _save(); },
        enabled: !_saving,
      ),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        FxButton(label: '取消', variant: FxButtonVariant.ghost,
          onPressed: _saving ? null : _cancel),
        const SizedBox(width: 8),
        FxButton(key: const ValueKey('account.nickname.save'),
          label: _saving ? '保存中…' : '保存',
          onPressed: _saving ? null : _save),
      ]),
    ],
    ),
  );
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({super.key, required this.alreadySet, required this.username});
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
  String? _usernameError;
  String? _oldError;
  String? _passwordError;
  String? _confirmError;
  String? _formError;

  @override
  void dispose() {
    _username.dispose();
    _old.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _hasDraft =>
      _username.text.trim().isNotEmpty ||
      _old.text.isNotEmpty ||
      _password.text.isNotEmpty ||
      _confirm.text.isNotEmpty;

  Future<void> _cancel() async {
    if (_saving) return;
    if (_hasDraft) {
      final confirmed = await FxDialog.confirm(
        context: context,
        title: '放弃未保存的密码修改？',
        content: '离开后尚未提交的账号和密码输入将丢失。',
        cancelText: '继续编辑',
        confirmText: '放弃修改',
        destructive: true,
        draftDiscard: true,
      );
      if (confirmed != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    if (_saving) return;
    final username = _username.text.trim();
    final password = _password.text;
    final invalidUsername = !widget.alreadySet &&
        (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{2,29}$').hasMatch(username) ||
         username.toLowerCase().startsWith('github_'));
    final invalidPassword =
        utf8.encode(password).length < 10 || utf8.encode(password).length > 72;
    final invalidConfirm = !invalidPassword && password != _confirm.text;
    final missingOld = widget.alreadySet && _old.text.isEmpty;
    setState(() {
      _usernameError = invalidUsername
          ? '账号须为 3–30 位字母、数字或下划线，以字母开头且不能使用 github_ 前缀'
          : null;
      _passwordError = invalidPassword ? '密码须为 10–72 字节' : null;
      _confirmError = invalidConfirm ? '两次输入的密码不一致' : null;
      _oldError = missingOld ? '请填写当前密码' : null;
      _formError = null;
    });
    if (invalidUsername || invalidPassword || invalidConfirm || missingOld) {
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
        await AuthService.setupPassword(username: username, password: password);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      FxNotice.recordError('账号密码操作失败', error);
      if (mounted) {
        final message = FxNotice.readableError(error);
        setState(() {
          if (message.contains('登录账号已被使用')) {
            _usernameError = '该登录账号已被使用，请更换';
          } else if (message.contains('原密码不正确')) {
            _oldError = message;
          } else {
            _formError = message;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.alreadySet) ...[
        const Text('设置后可以使用 GitHub 或账号密码登录同一个 Slowlight 账号。保存前需要重新验证 GitHub 身份。'),
        const SizedBox(height: 12),
        FxInput(
          key: const ValueKey('account.password.username'),
          label: '登录账号',
          placeholder: '3–30 位字母、数字、下划线',
          controller: _username,
          errorText: _usernameError,
          onChanged: (_) {
            if (_usernameError != null || _formError != null) {
              setState(() {
                _usernameError = null;
                _formError = null;
              });
            }
          },
          enabled: !_saving,
        ),
      ] else ...[
        Text('登录账号：${widget.username}'),
        const SizedBox(height: 12),
        FxInput(
          label: '当前密码',
          controller: _old,
          errorText: _oldError,
          onChanged: (_) {
            if (_oldError != null || _formError != null) {
              setState(() {
                _oldError = null;
                _formError = null;
              });
            }
          },
          obscureText: true,
          enabled: !_saving,
        ),
      ],
      const SizedBox(height: 12),
      FxInput(
        key: const ValueKey('account.password.new'),
        label: widget.alreadySet ? '新密码' : '登录密码',
        controller: _password,
        errorText: _passwordError,
        onChanged: (_) {
          if (_passwordError != null || _confirmError != null ||
              _formError != null) {
            setState(() {
              _passwordError = null;
              _confirmError = null;
              _formError = null;
            });
          }
        },
        obscureText: true,
        enabled: !_saving,
      ),
      const SizedBox(height: 12),
      FxInput(
        label: '确认密码',
        controller: _confirm,
        errorText: _confirmError,
        onChanged: (_) {
          if (_confirmError != null || _formError != null) {
            setState(() {
              _confirmError = null;
              _formError = null;
            });
          }
        },
        obscureText: true,
        enabled: !_saving,
      ),
      if (_formError != null) ...[
        const SizedBox(height: SlowlightSpacing.md),
        Text(
          _formError!,
          key: const ValueKey('account.password.form_error'),
          style: SlowlightTypography.secondary(context)
              .copyWith(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        FxButton(label: '取消', variant: FxButtonVariant.ghost,
          onPressed: _saving ? null : _cancel),
        const SizedBox(width: 8),
        FxButton(key: const ValueKey('account.password.save'),
          label: _saving ? '处理中…' : widget.alreadySet ? '修改密码' : '验证并设置',
          onPressed: _saving ? null : _save),
      ]),
    ],
    ),
  );
}
