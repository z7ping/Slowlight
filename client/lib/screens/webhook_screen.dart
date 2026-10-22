import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../brand.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

class WebhookEventDef {
  final String key;
  final String label;
  final IconData icon;
  final String description;
  final String exampleUse;
  final String examplePayload;

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
    icon: LucideIcons.check,
    description: '用户标记任务为已完成时触发',
    exampleUse: '完成任务后自动同步到飞书、发 Slack 通知',
    examplePayload:
        '{"event":"task.completed","data":{"id":42,"title":"写周报","list_id":1}}',
  ),
  WebhookEventDef(
    key: 'task.created',
    label: '任务创建',
    icon: LucideIcons.plus,
    description: '用户创建新任务时触发',
    exampleUse: '新任务自动创建 Notion 页面、推送到 Todoist',
    examplePayload:
        '{"event":"task.created","data":{"id":43,"title":"买牛奶","list_id":2}}',
  ),
  WebhookEventDef(
    key: 'task.updated',
    label: '任务更新',
    icon: LucideIcons.pencil,
    description: '用户编辑任务标题、描述、优先级等字段时触发',
    exampleUse: '任务变更时同步到外部系统',
    examplePayload:
        '{"event":"task.updated","data":{"id":42,"title":"写周报(改)","priority":"high"}}',
  ),
  WebhookEventDef(
    key: 'task.deleted',
    label: '任务删除',
    icon: LucideIcons.trash2,
    description: '用户删除任务时触发',
    exampleUse: '删除任务时清理外部系统的对应记录',
    examplePayload: '{"event":"task.deleted","data":{"id":42,"title":"写周报"}}',
  ),
  WebhookEventDef(
    key: 'habit.checked',
    label: '习惯打卡',
    icon: LucideIcons.repeat2,
    description: '用户完成一次习惯打卡时触发',
    exampleUse: '打卡后自动写入 Google Sheets、发朋友圈文案',
    examplePayload:
        '{"event":"habit.checked","data":{"habit_id":5,"name":"早起","streak_count":7}}',
  ),
  WebhookEventDef(
    key: 'session.ended',
    label: '番茄钟结束',
    icon: LucideIcons.timer,
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
  List<dynamic> _webhooks = const [];
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _loadFailed = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadWebhooks();
  }

  Future<void> _loadWebhooks() async {
    if (mounted && !_hasLoaded) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    try {
      final webhooks = await ApiService.getWebhooks();
      if (!mounted) return;
      setState(() {
        _webhooks = webhooks;
        _isLoading = false;
        _hasLoaded = true;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
      if (_hasLoaded) _showMsg('事件回调刷新失败，仍显示上次加载的记录');
    }
  }

  Future<void> _addWebhook() async {
    if (_creating) return;
    final result = await FxDialog.show<Map<String, dynamic>>(
      context: context,
      title: '添加事件回调',
      width: 560,
      child: const _AddWebhookDialogBody(),
    );
    if (result == null || !mounted || _creating) return;
    setState(() => _creating = true);
    final url = (result['url'] as String).trim();
    final events = result['events'] as List<String>;
    var created = 0;
    var skipped = 0;
    try {
      // 逐次按「地址 + 事件」核对服务端已确认记录，
      // 不用旧列表推断不存在，防止批量部分成功后再次创建重复回调。
      final existing = await ApiService.getWebhooks();
      final present = <String>{
        for (final item in existing)
          if (item is Map &&
              item['url']?.toString().trim() == url &&
              item['event'] != null)
            item['event'].toString(),
      };
      for (final event in events.toSet()) {
        if (present.contains(event)) {
          skipped++;
          continue;
        }
        try {
          await ApiService.createWebhook(
            url: url, event: event,
            name: result['name'] as String? ?? '',
          );
          created++;
          present.add(event);
        } catch (error) {
          _showMsg(
            '已确认创建 $created 条、跳过重复 $skipped 条。'
            '「$event」创建结果未确认：$error。'
            '请核对最新列表后再添加剩余事件，避免重复回调。',
          );
          await _loadWebhooks();
          return;
        }
      }
      await _loadWebhooks();
      _showMsg('已创建 $created 条，已有 $skipped 条跳过重复创建');
    } catch (error) {
      _showMsg('无法核对已有回调，未继续批量创建：$error');
      await _loadWebhooks();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _testWebhook(int id) async {
    try {
      final result = await ApiService.testWebhook(id);
      _showMsg(result['success'] == true ? '测试成功' : '测试失败: ${result['error']}');
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
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ApiService.deleteWebhook(id);
      await _loadWebhooks();
    } catch (e) {
      _showMsg('删除失败：$e');
    }
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    FxNotice.showContent(context, Text(msg));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: '事件回调',
              actionIcon: LucideIcons.plus,
              actionTooltip: '添加事件回调',
              onAction: _creating ? null : _addWebhook,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: FxCircularProgress())
                  : _loadFailed && !_hasLoaded
                  ? FxEmptyState(
                      icon: LucideIcons.triangleAlert,
                      title: '事件回调加载失败',
                      subtitle: '暂时无法获取现有配置，请检查连接后重试。',
                      action: FxButton(
                        label: '重新加载',
                        variant: FxButtonVariant.secondary,
                        onPressed: _loadWebhooks,
                      ),
                    )
                  : _webhooks.isEmpty
                  ? FxEmptyState(
                      icon: LucideIcons.link2,
                      title: '还没有事件回调',
                      subtitle: '连接 $kBrandDisplayName 到 n8n、Zapier 等外部服务',
                    )
                  : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._webhooks.map(_buildWebhookCard),
        const SizedBox(height: 24),
        _buildEventGuide(),
      ],
    );
  }

  Widget _buildWebhookCard(dynamic webhook) {
    final eventKey = webhook['event']?.toString() ?? '';
    final def = webhookEvents.firstWhere(
      (event) => event.key == eventKey,
      orElse:
          () => WebhookEventDef(
            key: eventKey,
            label: eventKey,
            icon: LucideIcons.link2,
            description: '',
            exampleUse: '',
            examplePayload: '',
          ),
    );

    return FxCard(
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: SlowlightRadius.lg,
      padding: EdgeInsets.zero,
      child: FxListTile(
        leading: CircleAvatar(
          backgroundColor:
              webhook['is_active'] == true
                  ? AppTheme.primaryLight
                  : Theme.of(context).colorScheme.outlineVariant,
          child: Icon(def.icon, size: SlowlightIconSize.md),
        ),
        title: Text(
          webhook['name']?.toString().isNotEmpty == true
              ? webhook['name'].toString()
              : def.label,
          style: SlowlightTypography.cardTitle(context),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${def.label}',
              style: SlowlightTypography.caption(
                context,
              ).copyWith(color: AppTheme.primary),
            ),
            Text(
              webhook['url']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SlowlightTypography.caption(context),
            ),
          ],
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            FxIconButton(
              tooltip: '测试',
              icon: LucideIcons.send,
              onPressed: () => _testWebhook(webhook['id'] as int),
            ),
            FxIconButton(
              tooltip: '删除',
              icon: LucideIcons.trash2,
              foregroundColor: AppTheme.error,
              onPressed: () => _deleteWebhook(webhook['id'] as int),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventGuide() {
    return FxCard(
      borderRadius: SlowlightRadius.lg,
      padding: EdgeInsets.zero,
      child: FxExpansionTile(
        leading: Icon(LucideIcons.info, color: AppTheme.primary),
        title: Text('事件说明', style: SlowlightTypography.cardTitle(context)),
        subtitle: Text(
          '点击展开查看每个事件的触发时机和用法',
          style: SlowlightTypography.caption(context),
        ),
        children: webhookEvents.map(_buildEventGuideTile).toList(),
      ),
    );
  }

  Widget _buildEventGuideTile(WebhookEventDef def) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Icon(def.icon, size: SlowlightIconSize.md),
              Text(def.label, style: SlowlightTypography.cardTitle(context)),
              FxChip(label: def.key, variant: FxChipVariant.secondary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '触发：${def.description}',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            '用法：${def.exampleUse}',
            style: SlowlightTypography.secondary(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          FxButton(
            label: '查看示例数据',
            icon: LucideIcons.code2,
            variant: FxButtonVariant.ghost,
            size: FxButtonSize.sm,
            onPressed: () => _showPayloadDialog(def),
          ),
          if (def != webhookEvents.last)
            const FxSeparator.horizontal(height: 24),
        ],
      ),
    );
  }

  Future<void> _showPayloadDialog(WebhookEventDef def) {
    return FxDialog.show<void>(
      context: context,
      title: '${def.label} — 示例数据',
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: SelectableText(
                def.examplePayload,
                style: SlowlightTypography.caption(
                  context,
                ).copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FxButton(
              label: '关闭',
              variant: FxButtonVariant.ghost,
              size: FxButtonSize.sm,
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddWebhookDialogBody extends StatefulWidget {
  const _AddWebhookDialogBody();

  @override
  State<_AddWebhookDialogBody> createState() => _AddWebhookDialogBodyState();
}

class _AddWebhookDialogBodyState extends State<_AddWebhookDialogBody> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final Set<String> _selectedEvents = {'task.completed'};

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 620),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FxInput(controller: _nameCtrl, placeholder: '名称（可选）'),
            const SizedBox(height: 12),
            FxInput(controller: _urlCtrl, placeholder: '回调地址'),
            const SizedBox(height: 16),
            Text('选择触发事件（可多选）', style: SlowlightTypography.cardTitle(context)),
            const SizedBox(height: 8),
            ...webhookEvents.map(_buildEventCheckbox),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                FxButton(
                  label: '取消',
                  variant: FxButtonVariant.ghost,
                  onPressed:
                      () => Navigator.of(context, rootNavigator: true).pop(),
                ),
                FxButton(
                  label: '添加 (${_selectedEvents.length})',
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCheckbox(WebhookEventDef def) {
    final selected = _selectedEvents.contains(def.key);
    return FxInkWell(
      onTap: () => _setSelected(def.key, !selected),
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            FxCheckbox(
              value: selected,
              onChanged: (value) => _setSelected(def.key, value),
            ),
            const SizedBox(width: 10),
            Icon(def.icon, size: SlowlightIconSize.md),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.label,
                    style: SlowlightTypography.secondary(context),
                  ),
                  Text(
                    def.description,
                    style: SlowlightTypography.caption(context).copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  void _setSelected(String key, bool selected) {
    setState(() {
      selected ? _selectedEvents.add(key) : _selectedEvents.remove(key);
    });
  }

  void _submit() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || _selectedEvents.isEmpty) return;
    Navigator.of(context, rootNavigator: true).pop({
      'url': url,
      'events': _selectedEvents.toList(),
      'name': _nameCtrl.text.trim(),
    });
  }
}
