import 'package:flutter/material.dart';

import '../repositories/feishu_integration_repository.dart';
import '../services/data_mode_manager.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/high_fidelity/hf_page_header.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';

part 'feishu_screen_sections.dart';

class FeishuScreen extends StatefulWidget {
  const FeishuScreen({super.key});

  @override
  State<FeishuScreen> createState() => _FeishuScreenState();
}

class _FeishuScreenState extends State<FeishuScreen> {
  final _integration = FeishuIntegrationRepository();
  final _appIdController = TextEditingController();
  final _appSecretController = TextEditingController();
  final _tableUrlController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSyncing = false;
  bool _isImporting = false;
  bool _isCreatingTemplate = false;
  bool _isConfigured = false;
  bool _isSyncingSessions = false;
  bool _isSyncingReminders = false;
  bool _isSyncingTags = false;
  bool _isSyncingAll = false;
  bool _isConnecting = false;
  bool _isSyncingCalendar = false;
  bool _isLoadingCalendars = false;
  bool _showSecret = false;
  String? _loadError;
  List<dynamic> _calendars = [];
  String? _selectedCalendarId;
  Map<String, dynamic> _tables = {};

  bool get _cloud => DataModeManager().isCloud;

  @override
  void initState() {
    super.initState();
    DataModeManager().addListener(_onDataModeChanged);
    _loadConfig();
  }

  @override
  void dispose() {
    DataModeManager().removeListener(_onDataModeChanged);
    _appIdController.dispose();
    _appSecretController.dispose();
    _tableUrlController.dispose();
    super.dispose();
  }

  void _onDataModeChanged() {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
      _isConfigured = false;
      _calendars = [];
      _selectedCalendarId = null;
      _tables = {};
      _appIdController.clear();
      _appSecretController.clear();
      _tableUrlController.clear();
    });
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _integration.config();
      if (!mounted) return;
      setState(() {
        _isConfigured = config['configured'] == true;
        _appIdController.text = config['app_id']?.toString() ?? '';
        _tableUrlController.text = config['table_url']?.toString() ?? '';
        _tables = Map<String, dynamic>.from(config['tables'] ?? const {});
        _loadError = null;
        _isLoading = false;
      });
      if (_isConfigured && _cloud) await _loadCalendars();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCalendars() async {
    if (!_cloud || _isLoadingCalendars) return;
    setState(() => _isLoadingCalendars = true);
    try {
      final calendars = await _integration.calendars();
      if (!mounted) return;
      setState(() {
        _calendars = calendars;
        if (_selectedCalendarId == null && calendars.isNotEmpty) {
          final primary = calendars.firstWhere(
            (item) => item['is_primary'] == true,
            orElse: () => calendars.first,
          );
          _selectedCalendarId = primary['id']?.toString();
        }
      });
    } catch (error) {
      if (mounted) _showError('读取飞书日历失败：$error');
    } finally {
      if (mounted) setState(() => _isLoadingCalendars = false);
    }
  }

  Future<void> _saveConfig() async {
    if (_appIdController.text.trim().isEmpty ||
        _appSecretController.text.trim().isEmpty) {
      _showError('请填写应用标识和应用密钥');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _integration.save(
        appId: _appIdController.text.trim(),
        appSecret: _appSecretController.text.trim(),
        tableUrl: _tableUrlController.text.trim().isEmpty
            ? null
            : _tableUrlController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _isConfigured = true;
        _appSecretController.clear();
        _showSecret = false;
      });
      _showSuccess('配置已安全保存');
      if (_cloud) await _loadCalendars();
    } catch (error) {
      if (mounted) _showError('保存失败：$error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _createTemplate() async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '创建飞书数据模板',
      content: '将在你的飞书空间中创建 8 张表：任务、子任务、清单、习惯、习惯记录、专注、休息记录和标签。',
      confirmText: '创建模板',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isCreatingTemplate = true);
    try {
      final result = await _integration.createTemplate();
      if (!mounted) return;
      final tableUrl =
          result['bitable_url']?.toString() ?? result['table_url']?.toString();
      setState(() {
        if (tableUrl?.isNotEmpty == true) _tableUrlController.text = tableUrl!;
        _tables = Map<String, dynamic>.from(result['tables'] ?? _tables);
      });
      _showSuccess('模板创建成功，表格链接已填入');
    } catch (error) {
      if (mounted) _showError('创建模板失败：$error');
    } finally {
      if (mounted) setState(() => _isCreatingTemplate = false);
    }
  }

  Future<void> _connectExisting() async {
    final url = _tableUrlController.text.trim();
    if (url.isEmpty) {
      _showError('请先填写飞书多维表格链接');
      return;
    }
    setState(() => _isConnecting = true);
    try {
      final result = await _integration.connect(url);
      if (!mounted) return;
      setState(() {
        _tables = Map<String, dynamic>.from(result['tables'] ?? const {});
        _isConfigured = true;
      });
      final allTables = (result['all_tables'] as List?)?.length;
      _showSuccess(
          '绑定成功，识别到 ${_tables.length}${allTables == null ? '' : ' / $allTables'} 张表');
    } catch (error) {
      if (mounted) _showError('绑定失败：$error');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _syncAll() async {
    setState(() => _isSyncingAll = true);
    try {
      final result = await _integration.syncAll();
      if (!mounted) return;
      final results = Map<String, dynamic>.from(result['results'] ?? const {});
      final errors = result['errors'] as List? ?? const [];
      final summary = results.entries
          .map((entry) => '${entry.key} ${entry.value} 条')
          .join(' · ');
      _showSuccess(errors.isEmpty
          ? (summary.isEmpty ? '同步完成' : '同步完成：$summary')
          : '同步完成，但有 ${errors.length} 个数据表失败');
    } catch (error) {
      if (mounted) _showError('同步全部失败：$error');
    } finally {
      if (mounted) setState(() => _isSyncingAll = false);
    }
  }

  Future<void> _syncToFeishu() => _runAction(
        start: () => _isSyncing = true,
        finish: () => _isSyncing = false,
        action: _integration.syncTasks,
        fallback: '任务同步完成',
        failure: '任务同步失败',
      );

  Future<void> _syncSessionsToFeishu() => _runAction(
        start: () => _isSyncingSessions = true,
        finish: () => _isSyncingSessions = false,
        action: _integration.syncSessions,
        fallback: '专注记录同步完成',
        failure: '专注记录同步失败',
      );

  Future<void> _syncRemindersToFeishu() => _runAction(
        start: () => _isSyncingReminders = true,
        finish: () => _isSyncingReminders = false,
        action: _integration.syncReminders,
        fallback: '休息记录同步完成',
        failure: '休息记录同步失败',
      );

  Future<void> _syncTagsToFeishu() => _runAction(
        start: () => _isSyncingTags = true,
        finish: () => _isSyncingTags = false,
        action: _integration.syncTags,
        fallback: '标签同步完成',
        failure: '标签同步失败',
      );

  Future<void> _importFromFeishu() => _runAction(
        start: () => _isImporting = true,
        finish: () => _isImporting = false,
        action: _integration.importData,
        fallback: '飞书数据导入完成',
        failure: '导入失败',
      );

  Future<void> _runAction({
    required VoidCallback start,
    required VoidCallback finish,
    required Future<Map<String, dynamic>> Function() action,
    required String fallback,
    required String failure,
  }) async {
    setState(start);
    try {
      final result = await action();
      if (mounted) _showSuccess(result['message']?.toString() ?? fallback);
    } catch (error) {
      if (mounted) _showError('$failure：$error');
    } finally {
      if (mounted) setState(finish);
    }
  }

  Future<void> _syncToCalendar() async {
    if (_selectedCalendarId == null) {
      _showError('请先选择一个飞书日历');
      return;
    }
    setState(() => _isSyncingCalendar = true);
    try {
      final result = await _integration.syncCalendar(_selectedCalendarId!);
      if (!mounted) return;
      final count = (result['results'] as Map<String, dynamic>?)?['日历事件'] ?? 0;
      _showSuccess('日历同步完成：$count 个事件');
    } catch (error) {
      if (mounted) _showError('日历同步失败：$error');
    } finally {
      if (mounted) setState(() => _isSyncingCalendar = false);
    }
  }

  void _showError(String message) => _message(message, error: true);
  void _showSuccess(String message) => _message(message);

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? theme.colorScheme.error : null,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const HfPageHeader(title: '飞书集成'),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? _buildLoadError()
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }
}
