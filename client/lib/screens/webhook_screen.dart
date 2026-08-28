import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../brand.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// Webhook 事件定义（带说明和示例）
class WebhookEventDef {
  final String key;
  final String label;
  final String icon;
  final String description; // 什么时候触发
  final String exampleUse; // 典型用法
  final String examplePayload; // 示例数据

  const WebhookEventDef({
    required this.key,
    required this.label,
    required this.icon,
    required this.description,
    required this.exampleUse,
    required this.examplePayload,
  });
}

const webhookEvents = [
  WebhookEventDef(
    key: 'task.completed',
    label: '任务完成',
    icon: '✅',
    description: '用户标记任务为已完成时触发',
    exampleUse: '完成任务后自动同步到飞书、发 Slack 通知',
    examplePayload:
        '{"event":"task.completed","data":{"id":42,"title":"写周报","list_id":1}}',
  ),
  WebhookEventDef(
    key: 'task.created',
    label: '任务创建',
    icon: '📝',
    description: '用户创建新任务时触发',
    exampleUse: '新任务自动创建 Notion 页面、推送到 Todoist',
    examplePayload:
        '{"event":"task.created","data":{"id":43,"title":"买牛奶","list_id":2}}',
  ),
  WebhookEventDef(
    key: 'task.updated',
    label: '任务更新',
    icon: '✏️',
    description: '用户编辑任务标题、描述、优先级等字段时触发',
    exampleUse: '任务变更时同步到外部系统',
    examplePayload:
        '{"event":"task.updated","data":{"id":42,"title":"写周报(改)","priority":"high"}}',
  ),
  WebhookEventDef(
    key: 'task.deleted',
    label: '任务删除',
    icon: '🗑️',
    description: '用户删除任务时触发',
    exampleUse: '删除任务时清理外部系统的对应记录',
    examplePayload: '{"event":"task.deleted","data":{"id":42,"title":"写周报"}}',
  ),
  WebhookEventDef(
    key: 'habit.checked',
    label: '习惯打卡',
    icon: '🔥',
    description: '用户完成一次习惯打卡时触发',
    exampleUse: '打卡后自动写入 Google Sheets、发朋友圈文案',
    examplePayload:
        '{"event":"habit.checked","data":{"habit_id":5,"name":"早起","streak_count":7}}',
  ),
  WebhookEventDef(
    key: 'session.ended',
    label: '番茄钟结束',
    icon: '🍅',
    description: '一次番茄钟专注或休息结束时触发',
    exampleUse: '专注结束自动记录 Toggl、更新日历',
    examplePayload:
        '{"event":"session.ended","data":{"session_type":"work","duration_sec":1500}}',
  ),
];

class WebhookScreen extends StatefulWidget {
  const WebhookScreen({super.key});

  @override
  State<WebhookScreen> createState() => _WebhookScreenState();
}

class _WebhookScreenState extends State<WebhookScreen> {
  List<dynamic> _webhooks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWebhooks();
  }

  Future<void> _loadWebhooks() async {
    try {
      final webhooks = await ApiService.getWebhooks();
      setState(() {
        _webhooks = webhooks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addWebhook() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _AddWebhookDialog(),
    );
    if (result != null) {
      try {
        // 如果选了多个事件，为每个事件创建一条 webhook
        final events = result['events'] as List<String>;
        for (final event in events) {
          await ApiService.createWebhook(
            url: result['url'] as String,
            event: event,
            name: result['name'] as String? ?? '',
          );
        }
        _loadWebhooks();
        _showMsg('创建成功 ${events.length} 条');
      } catch (e) {
        _showMsg('创建失败: $e');
      }
    }
  }

  Future<void> _testWebhook(int id) async {
    try {
      final result = await ApiService.testWebhook(id);
      _showMsg(
          result['success'] == true ? '测试成功 ✅' : '测试失败: ${result['error']}');
    } catch (e) {
      _showMsg('测试失败: $e');
    }
  }

  Future<void> _deleteWebhook(int id) async {
    final ok = await FxDialog.confirm(
      context: context,
      title: '确认删除',
      content: '删除后该事件回调将不再触发',
      confirmText: '删除',
    );
    if (ok == true) {
      await ApiService.deleteWebhook(id);
      _loadWebhooks();
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('事件回调'),
        actions: [
          IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _addWebhook),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _webhooks.isEmpty
              ? _buildEmpty()
              : _buildContent(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.webhook,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text('还没有事件回调',
              style: TextStyle(
                  fontSize: AppTheme.textLg,
                  color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 8),
          Text('连接 $kBrandDisplayName 到 n8n、Zapier 等外部服务',
              style: TextStyle(
                  fontSize: AppTheme.textMd,
                  color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 24),
          FxButton(
            label: '添加事件回调',
            variant: FxButtonVariant.outline,
            icon: Icons.add,
            onPressed: _addWebhook,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // 按事件类型分组
    final Map<String, List<dynamic>> grouped = {};
    for (final wh in _webhooks) {
      final event = wh['event'] ?? 'unknown';
      grouped.putIfAbsent(event, () => []).add(wh);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 已配置的 Webhook 列表
        ..._webhooks.map((wh) => _buildWebhookCard(wh)),

        const SizedBox(height: 24),
        // 事件说明卡片
        _buildEventGuide(),
      ],
    );
  }

  Widget _buildWebhookCard(dynamic wh) {
    final eventKey = wh['event'] ?? '';
    final def = webhookEvents.firstWhere(
      (e) => e.key == eventKey,
      orElse: () => WebhookEventDef(
        key: eventKey,
        label: eventKey,
        icon: '?',
        description: '',
        exampleUse: '',
        examplePayload: '',
      ),
    );

    return FxCard(
      margin: EdgeInsets.only(bottom: 8),
      borderRadius: 12,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: wh['is_active'] == true
              ? AppTheme.primaryLight
              : Theme.of(context).colorScheme.outlineVariant,
          child: Text(def.icon,
              style: const TextStyle(fontSize: AppTheme.textXl, height: 1.3)),
        ),
        title: Text(
          wh['name']?.isNotEmpty == true ? wh['name'] : def.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${def.icon} ${def.label}',
                style: TextStyle(
                    fontSize: AppTheme.textXs,
                    height: 1.4,
                    color: AppTheme.primary)),
            Text(wh['url'] ?? '',
                style: const TextStyle(fontSize: AppTheme.textXs, height: 1.4),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.send, size: 20),
                onPressed: () => _testWebhook(wh['id']),
                tooltip: '测试'),
            IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppTheme.error),
                onPressed: () => _deleteWebhook(wh['id'])),
          ],
        ),
      ),
    );
  }

  /// 事件说明卡片（展开/收起）
  Widget _buildEventGuide() {
    return FxCard(
      borderRadius: 12,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(Icons.info_outline, color: AppTheme.primary),
        title: const Text('事件说明',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppTheme.textMd,
                height: 1.5)),
        subtitle: const Text('点击展开查看每个事件的触发时机和用法',
            style: TextStyle(fontSize: AppTheme.textXs, height: 1.4)),
        children:
            webhookEvents.map((def) => _buildEventGuideTile(def)).toList(),
      ),
    );
  }

  Widget _buildEventGuideTile(WebhookEventDef def) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 事件名 + 图标
          Row(
            children: [
              Text(def.icon,
                  style:
                      const TextStyle(fontSize: AppTheme.textXl, height: 1.2)),
              const SizedBox(width: 8),
              Text(def.label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: AppTheme.textMd,
                      height: 1.5)),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(def.key,
                    style: TextStyle(
                        fontSize: AppTheme.textXs,
                        height: 1.4,
                        fontFamily: 'monospace',
                        color: AppTheme.primary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 触发时机
          Text('触发：${def.description}',
              style: TextStyle(
                  fontSize: AppTheme.textMd,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          // 典型用法
          Text('用法：${def.exampleUse}',
              style: TextStyle(
                  fontSize: AppTheme.textMd,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          // 示例数据（可展开查看）
          FxInkWell(
            onTap: () => _showPayloadDialog(def),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.code,
                      size: 14, color: Theme.of(context).colorScheme.outline),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '查看示例数据 →',
                      style: TextStyle(
                          fontSize: AppTheme.textXs,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (def != webhookEvents.last) const Divider(height: 24),
        ],
      ),
    );
  }

  void _showPayloadDialog(WebhookEventDef def) {
    showShadDialog(
      context: context,
      builder: (ctx) => ShadDialog(
        title: Text('${def.icon} ${def.label} — 示例数据'),
        description: null,
        child: SingleChildScrollView(
          child: SelectableText(
            def.examplePayload,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: AppTheme.textXs,
                height: 1.4),
          ),
        ),
        actions: [
          ShadButton.ghost(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }
}

/// 添加 Webhook 对话框（支持多选事件）
class _AddWebhookDialog extends StatefulWidget {
  @override
  State<_AddWebhookDialog> createState() => _AddWebhookDialogState();
}

class _AddWebhookDialogState extends State<_AddWebhookDialog> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final Set<String> _selectedEvents = {'task.completed'};

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: const Text('添加事件回调'),
      description: null,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FxInput(
              controller: _nameCtrl,
              placeholder: '名称（可选）',
            ),
            const SizedBox(height: 12),
            FxInput(
              controller: _urlCtrl,
              placeholder: '回调地址',
            ),
            const SizedBox(height: 16),
            const Text('选择触发事件（可多选）',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppTheme.textMd,
                    height: 1.5)),
            const SizedBox(height: 8),
            // 事件多选列表
            ...webhookEvents.map((def) => _buildEventCheckbox(def)),
          ],
        ),
      ),
      actions: [
        ShadButton.ghost(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FxButton(
          label: '添加 (${_selectedEvents.length})',
          onPressed: () {
            if (_urlCtrl.text.trim().isEmpty || _selectedEvents.isEmpty) return;
            Navigator.pop(context, {
              'url': _urlCtrl.text.trim(),
              'events': _selectedEvents.toList(),
              'name': _nameCtrl.text.trim(),
            });
          },
        ),
      ],
    );
  }

  Widget _buildEventCheckbox(WebhookEventDef def) {
    final selected = _selectedEvents.contains(def.key);
    return FxInkWell(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedEvents.remove(def.key);
          } else {
            _selectedEvents.add(def.key);
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: FxCheckbox(
                value: selected,
                onChanged: (v) {
                  setState(() {
                    if (v) {
                      _selectedEvents.add(def.key);
                    } else {
                      _selectedEvents.remove(def.key);
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            Text(def.icon,
                style: const TextStyle(fontSize: AppTheme.textXl, height: 1.3)),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(def.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: AppTheme.textMd,
                          height: 1.5)),
                  Text(def.description,
                      style: TextStyle(
                          fontSize: AppTheme.textXs,
                          height: 1.4,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
