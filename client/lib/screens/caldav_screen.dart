import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// CalDAV 配置页面
class CalDAVScreen extends StatefulWidget {
  const CalDAVScreen({super.key});

  @override
  State<CalDAVScreen> createState() => _CalDAVScreenState();
}

class _CalDAVScreenState extends State<CalDAVScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pathsController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _configured = false;
  bool _obscurePassword = true;

  Map<String, dynamic>? _status;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathsController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await ApiService.getCalDAVConfig();
      if (!mounted) return;
      setState(() {
        _configured = config['configured'] ?? false;
        if (_configured && config['value'] != null) {
          final value = config['value'];
          if (value is Map) {
            _baseUrlController.text = value['base_url'] ?? '';
            _usernameController.text = value['username'] ?? '';
            if (value['paths'] != null) {
              _pathsController.text = (value['paths'] as List).join('\n');
            }
          }
        }
        _loading = false;
      });

      if (_configured) {
        _loadStatus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lastError = e.toString();
      });
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await ApiService.getCalDAVStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {}
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _lastError = null;
    });

    try {
      final result = await ApiService.testCalDAVConnection(
        baseUrl: _baseUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        paths:
            _pathsController.text
                .split('\n')
                .where((p) => p.trim().isNotEmpty)
                .map((p) => p.trim())
                .toList(),
      );

      if (mounted) {
        final connected = result['connected'] ?? false;
        final queryOk = result['query_ok'] ?? false;
        final taskCount = result['task_count'] ?? 0;
        final error = result['error'] as String?;

        String message;
        FxNoticeVariant noticeVariant;
        if (connected && queryOk) {
          message = '连接成功！找到 $taskCount 个任务';
          noticeVariant = FxNoticeVariant.success;
        } else if (connected) {
          message = '已连接，但查询失败：${error ?? "未知错误"}';
          noticeVariant = FxNoticeVariant.warning;
        } else {
          message = '连接失败：${error ?? "未知错误"}';
          noticeVariant = FxNoticeVariant.destructive;
        }

        FxNotice.showContent(
          context,
          Text(message),
          duration: const Duration(seconds: 3),
          variant: noticeVariant,
        );
      }
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(
          context,
          Text('测试失败：$e'),
          duration: const Duration(seconds: 3),
          variant: FxNoticeVariant.destructive,
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _lastError = null;
    });

    try {
      await ApiService.saveCalDAVConfig(
        baseUrl: _baseUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        paths:
            _pathsController.text
                .split('\n')
                .where((p) => p.trim().isNotEmpty)
                .map((p) => p.trim())
                .toList(),
      );

      if (!mounted) return;
      setState(() {
        _configured = true;
        _saving = false;
      });

      _loadStatus();

      FxNotice.showContent(
        context,
        Text('配置保存成功！系统将每5分钟自动同步'),
        duration: Duration(seconds: 3),
        variant: FxNoticeVariant.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _lastError = e.toString();
      });

      FxNotice.showContent(
        context,
        Text('保存失败：$e'),
        duration: const Duration(seconds: 3),
        variant: FxNoticeVariant.destructive,
      );
    }
  }

  Future<void> _syncNow() async {
    try {
      final result = await ApiService.syncCalDAV();
      if (mounted) {
        final created = result['tasks_created'] ?? 0;
        final updated = result['tasks_updated'] ?? 0;
        final skipped = result['tasks_skipped'] ?? 0;
        final errors = result['errors'] as List?;

        String message = '同步完成：创建 $created，更新 $updated，跳过 $skipped';
        if (errors != null && errors.isNotEmpty) {
          message += '\n错误：${errors.length} 个';
        }

        FxNotice.showContent(
          context,
          Text(message),
          duration: const Duration(seconds: 5),
          variant:
              errors?.isNotEmpty == true
                  ? FxNoticeVariant.warning
                  : FxNoticeVariant.success,
        );

        _loadStatus();
      }
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(
          context,
          Text('同步失败：$e'),
          duration: const Duration(seconds: 3),
          variant: FxNoticeVariant.destructive,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CalDAV 同步'),
        elevation: 0,
        actions: [
          if (_configured)
            FxIconButton(
              icon: Icons.sync,
              onPressed: _syncNow,
              tooltip: '立即同步',
            ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body:
          _loading
              ? const Center(child: FxCircularProgress())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoCard(),
                    const SizedBox(height: 16),
                    _buildConfigForm(),
                    const SizedBox(height: 16),
                    if (_configured) _buildStatusCard(),
                    if (_lastError != null) ...[
                      const SizedBox(height: 16),
                      _buildErrorCard(),
                    ],
                  ],
                ),
              ),
    );
  }

  Widget _buildInfoCard() {
    return FxCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'CalDAV 同步',
                  style: TextStyle(
                    fontSize: AppTheme.textMd,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '配置后系统将：',
              style: TextStyle(
                fontSize: AppTheme.textMd,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            _buildInfoItem('📥', '自动同步远程任务到本地'),
            _buildInfoItem('📤', '支持双向同步（创建/更新）'),
            _buildInfoItem('⏰', '每5分钟自动检查更新'),
            _buildInfoItem('🏷️', '保持任务优先级、截止日期等属性'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.success.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📝 快速上手：',
                    style: TextStyle(
                      fontSize: AppTheme.textMd,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '1. 填写服务器地址（如 https://vikunja.example.com）\n'
                    '2. 输入用户名和密码 / 访问令牌\n'
                    '3. 填写项目路径（格式 /dav/projects/ID）\n'
                    '4. 点击「测试连接」验证\n'
                    '5. 点击「保存配置」完成',
                    style: TextStyle(
                      fontSize: AppTheme.textXs,
                      color: AppTheme.success,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.info.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 支持的服务：',
                    style: TextStyle(
                      fontSize: AppTheme.textMd,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.info,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Vikunja — 开源任务管理\n'
                    '• Nextcloud Tasks — 自托管任务\n'
                    '• Baïkal / Radicale — 轻量 CalDAV\n'
                    '• 任何兼容 CalDAV 协议的服务',
                    style: TextStyle(
                      fontSize: AppTheme.textXs,
                      color: AppTheme.info,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.priorityLow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.priorityLow.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📍 项目路径获取：',
                    style: TextStyle(
                      fontSize: AppTheme.textMd,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.priorityLow,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Vikunja：项目设置 → 复制 CalDAV 路径\n'
                    '• Nextcloud：任务设置 → 复制 CalDAV 地址\n'
                    '• 一般格式：/dav/projects/{数字ID}',
                    style: TextStyle(
                      fontSize: AppTheme.textXs,
                      color: AppTheme.priorityLow,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: AppTheme.textMd, height: 1.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: AppTheme.textMd, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigForm() {
    return FxCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '连接配置',
                style: TextStyle(
                  fontSize: AppTheme.textMd,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://vikunja.example.com',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入服务器地址';
                  }
                  if (!value.startsWith('http://') &&
                      !value.startsWith('https://')) {
                    return '请输入有效地址（以 http:// 或 https:// 开头）';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  hintText: '输入 CalDAV 用户名',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入用户名';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码 / 访问令牌',
                  hintText: '输入密码或访问令牌',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: FxIconButton(
                    icon:
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入密码或访问令牌';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pathsController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '项目路径（每行一个）',
                  hintText: '/dav/projects/5\n/dav/projects/8',
                  prefixIcon: Icon(Icons.folder),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请至少输入一个项目路径';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                '格式：/dav/projects/{项目ID}，可在 Vikunja 项目设置中查看',
                style: TextStyle(
                  fontSize: AppTheme.textXs,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FxButton(
                      label: '测试连接',
                      onPressed: _testing ? null : _testConnection,
                      variant: FxButtonVariant.outline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FxButton(
                      label: '保存配置',
                      onPressed: _saving ? null : _saveConfig,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return FxCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '同步状态',
                  style: TextStyle(
                    fontSize: AppTheme.textMd,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusItem('服务器', _baseUrlController.text),
            _buildStatusItem('用户', _usernameController.text),
            _buildStatusItem('已同步任务', '${_status?['task_count'] ?? 0} 个'),
            if (_status?['states'] != null) ...[
              const SizedBox(height: 8),
              const Text(
                '同步历史：',
                style: TextStyle(
                  fontSize: AppTheme.textMd,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              ...(_status!['states'] as List).map((state) {
                final path = state['project_path'] ?? '未知';
                final lastSync = state['last_synced_at'] ?? '从未同步';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• $path - 最后同步：$lastSync',
                    style: const TextStyle(
                      fontSize: AppTheme.textXs,
                      height: 1.4,
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FxButton(label: '立即同步', onPressed: _syncNow),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTheme.textMd,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: AppTheme.textMd, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return FxCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '错误信息',
                  style: TextStyle(
                    fontSize: AppTheme.textMd,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _lastError!,
              style: const TextStyle(
                fontSize: AppTheme.textMd,
                height: 1.5,
                color: AppTheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
