import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../repositories/feishu_integration_repository.dart';
import '../services/data_mode_manager.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

part 'feishu_screen_sections.dart';

class FeishuScreen extends StatefulWidget {
  final FeishuIntegrationRepository? repository;

  const FeishuScreen({super.key, this.repository});

  @override
  State<FeishuScreen> createState() => _FeishuScreenState();
}

class _FeishuScreenState extends State<FeishuScreen> {
  late final FeishuIntegrationRepository _integration;
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
  bool _editingConfiguration = false;
  bool _guideExpanded = false;
  bool _confirmingExit = false;
  bool _exitApproved = false;
  String _savedAppId = '';
  String _savedTableUrl = '';
  String? _loadError;
  List<dynamic> _calendars = [];
  String? _selectedCalendarId;
  Map<String, dynamic> _tables = {};
  int _sourceVersion = 0;
  int _configReadVersion = 0;
  int _calendarReadVersion = 0;

  // Data mode is a source boundary. An earlier Local/Cloud request can still
  // finish after switching; its response must not populate the new mode.
  bool _sameSource(int version, bool wasCloud) =>
      mounted && version == _sourceVersion && _cloud == wasCloud;

  bool get _cloud => DataModeManager().isCloud;

  bool get _tablesReady =>
      _isConfigured && _tableUrlController.text.trim().isNotEmpty &&
      _tables.isNotEmpty;

  bool _hasTable(String name) =>
      _tablesReady && (_tables[name]?.toString().isNotEmpty ?? false);

  bool get _canSyncAll =>
      const ['任务表', '番茄钟表', '休息提醒表', '标签表'].every(_hasTable);

  bool get _hasConfigurationDraft =>
      _appIdController.text.trim() != _savedAppId ||
      _tableUrlController.text.trim() != _savedTableUrl ||
      _appSecretController.text.isNotEmpty;

  bool get _hasPendingCredentialChanges =>
      _appIdController.text.trim() != _savedAppId ||
      _appSecretController.text.isNotEmpty;

  void _leaveAfterFrame() {
    if (!mounted || _exitApproved) return;
    setState(() => _exitApproved = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  Future<void> _confirmDiscardAndLeave() async {
    if (_confirmingExit) return;
    _confirmingExit = true;
    try {
      final confirmed = await FxDialog.confirm(
        context: context,
        title: '放弃飞书配置修改？',
        content: '未保存的应用标识、密钥和表格链接将丢失。',
        confirmText: '放弃修改',
      );
      if (confirmed == true && mounted) _leaveAfterFrame();
    } finally {
      _confirmingExit = false;
    }
  }

  /// 所有可能修改外部平台数据的操作共用互斥门禁。
  /// 避免「同步全部」与单项同步/导入/创建模板同时提交。
  bool get _busyWithFeishu => _isSaving || _isCreatingTemplate ||
      _isConnecting || _isSyncingAll || _isSyncing || _isSyncingSessions ||
      _isSyncingReminders || _isSyncingTags || _isImporting || _isSyncingCalendar;

  @override
  void initState() {
    super.initState();
    _integration = widget.repository ?? FeishuIntegrationRepository();
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
    final oldWritePending = _busyWithFeishu;
    final oldDraftPending = _hasConfigurationDraft;
    ++_sourceVersion;
    ++_configReadVersion;
    ++_calendarReadVersion;
    setState(() {
      // The previous source's write may continue remotely, but must not keep
      // the new source locked or clear its independent busy flags on return.
      _isSaving = false;
      _isCreatingTemplate = false;
      _isConnecting = false;
      _isSyncingAll = false;
      _isSyncing = false;
      _isSyncingSessions = false;
      _isSyncingReminders = false;
      _isSyncingTags = false;
      _isImporting = false;
      _isSyncingCalendar = false;
      _isLoading = true;
      _isLoadingCalendars = false;
      _loadError = null;
      _isConfigured = false;
      _calendars = [];
      _selectedCalendarId = null;
      _tables = {};
      _showSecret = false;
      _editingConfiguration = false;
      _savedAppId = '';
      _savedTableUrl = '';
      _appIdController.clear();
      _appSecretController.clear();
      _tableUrlController.clear();
    });
    _loadConfig();
    if (oldDraftPending) _showWarning('数据模式已切换，未保存的飞书配置草稿已丢弃。');
    if (oldWritePending) {
      _showWarning('数据模式已切换。上一个模式的飞书操作结果未确认，'
          '请先核对飞书记录，避免重复提交。');
    }
  }

  Future<void> _loadConfig() async {
    final source = _sourceVersion;
    final wasCloud = _cloud;
    final read = ++_configReadVersion;
    bool current() => _sameSource(source, wasCloud) &&
        read == _configReadVersion;
    try {
      final config = await _integration.config();
      if (!current()) return;
      setState(() {
        _isConfigured = config['configured'] == true;
        _appIdController.text = config['app_id']?.toString() ?? '';
        _tableUrlController.text = config['table_url']?.toString() ?? '';
        _savedAppId = _appIdController.text.trim();
        _savedTableUrl = _tableUrlController.text.trim();
        _editingConfiguration = false;
        _tables = Map<String, dynamic>.from(config['tables'] ?? const {});
        _loadError = null;
        _isLoading = false;
      });
      if (_isConfigured && wasCloud) await _loadCalendars();
    } catch (error) {
      if (!current()) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCalendars() async {
    if (!_cloud || _isLoadingCalendars) return;
    final source = _sourceVersion;
    final read = ++_calendarReadVersion;
    bool current() => _sameSource(source, true) &&
        read == _calendarReadVersion;
    setState(() => _isLoadingCalendars = true);
    try {
      final calendars = await _integration.calendars();
      if (!current()) return;
      setState(() {
        _calendars = calendars;
        if (!calendars.any((item) => item['id']?.toString() == _selectedCalendarId)) {
          if (calendars.isEmpty) {
            _selectedCalendarId = null;
          } else {
            final primary = calendars.firstWhere(
              (item) => item['is_primary'] == true,
              orElse: () => calendars.first,
            );
            _selectedCalendarId = primary['id']?.toString();
          }
        }
      });
    } catch (error) {
      if (current()) _showError('读取飞书日历失败：$error');
    } finally {
      if (current()) setState(() => _isLoadingCalendars = false);
    }
  }

  Future<void> _saveConfig() async {
    if (_busyWithFeishu) return;
    if (_appIdController.text.trim().isEmpty ||
        _appSecretController.text.trim().isEmpty) {
      _showError('请填写应用标识和应用密钥');
      return;
    }
    final source = _sourceVersion;
    final wasCloud = _cloud;
    final nextAppId = _appIdController.text.trim();
    final nextTableUrl = _tableUrlController.text.trim();
    final mappingChanged = nextAppId != _savedAppId || nextTableUrl != _savedTableUrl;
    setState(() => _isSaving = true);
    try {
      await _integration.save(
        appId: _appIdController.text.trim(),
        appSecret: _appSecretController.text.trim(),
        tableUrl:
            _tableUrlController.text.trim().isEmpty
                ? null
                : _tableUrlController.text.trim(),
      );
      if (!_sameSource(source, wasCloud)) return;
      setState(() {
        _isConfigured = true;
        if (mappingChanged) _tables = {};
        _savedAppId = nextAppId;
        _savedTableUrl = nextTableUrl;
        _editingConfiguration = false;
        _appSecretController.clear();
        _showSecret = false;
      });
      _showSuccess(_tablesReady ? '应用凭据已保存' : '应用凭据已保存，请继续创建或绑定数据表');
      if (wasCloud) await _loadCalendars();
    } catch (error) {
      if (_sameSource(source, wasCloud)) _showError('保存失败：$error');
    } finally {
      if (_sameSource(source, wasCloud)) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _createTemplate() async {
    if (_busyWithFeishu || !_isConfigured) return;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '创建飞书数据模板',
      content: '将在你的飞书空间中创建 8 张表：任务、子任务、清单、习惯、习惯记录、专注、休息记录和标签。',
      confirmText: '创建模板',
    );
    if (confirmed != true || !mounted || _busyWithFeishu) return;
    final source = _sourceVersion;
    final wasCloud = _cloud;
    setState(() => _isCreatingTemplate = true);
    try {
      final result = await _integration.createTemplate();
      if (!_sameSource(source, wasCloud)) return;
      final tableUrl =
          result['bitable_url']?.toString() ?? result['table_url']?.toString();
      setState(() {
        if (tableUrl?.isNotEmpty == true) {
          _tableUrlController.text = tableUrl!;
          _savedTableUrl = tableUrl;
        }
        _tables = Map<String, dynamic>.from(result['tables'] ?? _tables);
      });
      _showSuccess('模板创建成功，表格链接已填入');
    } catch (error) {
      if (_sameSource(source, wasCloud)) _showError('创建模板失败：$error');
    } finally {
      if (_sameSource(source, wasCloud)) {
        setState(() => _isCreatingTemplate = false);
      }
    }
  }

  Future<void> _connectExisting() async {
    if (_busyWithFeishu || !_isConfigured) return;
    if (_hasPendingCredentialChanges) {
      _showError('应用凭据有未保存的修改，请先保存配置');
      return;
    }
    final url = _tableUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _editingConfiguration = true);
      _showError('请先在连接配置中填写飞书多维表格链接');
      return;
    }
    final source = _sourceVersion;
    final wasCloud = _cloud;
    setState(() => _isConnecting = true);
    try {
      final result = await _integration.connect(url);
      if (!_sameSource(source, wasCloud)) return;
      setState(() {
        _tables = Map<String, dynamic>.from(result['tables'] ?? const {});
        _isConfigured = true;
        _savedTableUrl = url;
        _editingConfiguration = false;
      });
      final allTables = (result['all_tables'] as List?)?.length;
      _showSuccess(
        '绑定成功，识别到 ${_tables.length}${allTables == null ? '' : ' / $allTables'} 张表',
      );
    } catch (error) {
      if (_sameSource(source, wasCloud)) _showError('绑定失败：$error');
    } finally {
      if (_sameSource(source, wasCloud)) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _syncAll() async {
    if (_busyWithFeishu || !_canSyncAll) return;
    final source = _sourceVersion;
    final wasCloud = _cloud;
    setState(() => _isSyncingAll = true);
    try {
      final result = await _integration.syncAll();
      if (!_sameSource(source, wasCloud)) return;
      final results = Map<String, dynamic>.from(result['results'] ?? const {});
      final errors = result['errors'] as List? ?? const [];
      final summary = results.entries
          .map((entry) => '${entry.key} ${entry.value} 条')
          .join(' · ');
      if (errors.isNotEmpty) {
        final detail = errors.take(4).map((item) {
          if (item is Map) {
            final group = item['type'] ?? item['table'] ?? item['name'];
            final message = item['error'] ?? item['message'] ?? '同步未完成';
            return group == null ? '$message' : '$group：$message';
          }
          return '$item';
        }).join('；');
        _showWarning('部分同步失败（${errors.length} 项）'
            '${summary.isEmpty ? '' : '，已成功：$summary'}。'
            '${detail.isEmpty ? '' : '失败详情：$detail。'}'
            '请核对飞书表格后再重试失败范围。');
      } else {
        _showSuccess(summary.isEmpty ? '同步完成' : '同步完成：$summary');
      }
    } catch (error) {
      if (_sameSource(source, wasCloud)) _showError('同步全部失败：$error');
    } finally {
      if (_sameSource(source, wasCloud)) {
        setState(() => _isSyncingAll = false);
      }
    }
  }

  Future<void> _syncToFeishu() => _runAction(
    start: () => _isSyncing = true,
    finish: () => _isSyncing = false,
    action: _integration.syncTasks,
    requiredTable: '任务表',
    fallback: '任务同步完成',
    failure: '任务同步失败',
  );

  Future<void> _syncSessionsToFeishu() => _runAction(
    start: () => _isSyncingSessions = true,
    finish: () => _isSyncingSessions = false,
    action: _integration.syncSessions,
    requiredTable: '番茄钟表',
    fallback: '专注记录同步完成',
    failure: '专注记录同步失败',
  );

  Future<void> _syncRemindersToFeishu() => _runAction(
    start: () => _isSyncingReminders = true,
    finish: () => _isSyncingReminders = false,
    action: _integration.syncReminders,
    requiredTable: '休息提醒表',
    fallback: '休息记录同步完成',
    failure: '休息记录同步失败',
  );

  Future<void> _syncTagsToFeishu() => _runAction(
    start: () => _isSyncingTags = true,
    finish: () => _isSyncingTags = false,
    action: _integration.syncTags,
    requiredTable: '标签表',
    fallback: '标签同步完成',
    failure: '标签同步失败',
  );

  Future<void> _importFromFeishu() => _runAction(
    start: () => _isImporting = true,
    finish: () => _isImporting = false,
    action: _integration.importData,
    requiredTable: '任务表',
    fallback: '飞书数据导入完成',
    failure: '导入失败',
  );

  Future<void> _runAction({
    required VoidCallback start,
    required VoidCallback finish,
    required Future<Map<String, dynamic>> Function() action,
    required String requiredTable,
    required String fallback,
    required String failure,
  }) async {
    if (_busyWithFeishu || !_hasTable(requiredTable)) return;
    final source = _sourceVersion;
    final wasCloud = _cloud;
    setState(start);
    try {
      final result = await action();
      if (_sameSource(source, wasCloud)) {
        _showSuccess(result['message']?.toString() ?? fallback);
      }
    } catch (error) {
      if (_sameSource(source, wasCloud)) _showError('$failure：$error');
    } finally {
      if (_sameSource(source, wasCloud)) setState(finish);
    }
  }

  Future<void> _syncToCalendar() async {
    if (_busyWithFeishu || !_isConfigured || !_cloud) return;
    if (_selectedCalendarId == null) {
      _showError('请先选择一个飞书日历');
      return;
    }
    final source = _sourceVersion;
    final wasCloud = _cloud;
    setState(() => _isSyncingCalendar = true);
    try {
      final result = await _integration.syncCalendar(_selectedCalendarId!);
      if (!_sameSource(source, wasCloud)) return;
      final count = (result['results'] as Map<String, dynamic>?)?['日历事件'] ?? 0;
      _showSuccess('日历同步完成：$count 个事件');
    } catch (error) {
      if (_sameSource(source, wasCloud)) _showError('日历同步失败：$error');
    } finally {
      if (_sameSource(source, wasCloud)) {
        setState(() => _isSyncingCalendar = false);
      }
    }
  }

  void _showError(String message) => _message(message, variant: FxNoticeVariant.destructive);
  void _showWarning(String message) => _message(message, variant: FxNoticeVariant.warning);
  void _showSuccess(String message) => _message(message);

  void _message(String message, {FxNoticeVariant variant = FxNoticeVariant.normal}) {
    if (!mounted) return;
    FxNotice.showContent(
      context,
      Text(message),
      variant: variant,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _exitApproved,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_hasConfigurationDraft) {
          _confirmDiscardAndLeave();
        } else {
          _leaveAfterFrame();
        }
      },
      child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const FxPageHeader(title: '飞书多维表格'),
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: FxCircularProgress())
                      : _loadError != null
                      ? _buildLoadError()
                      : _buildContent(),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
