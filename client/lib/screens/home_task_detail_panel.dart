import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// 桌面端任务详情面板（右侧三栏）
class HomeTaskDetailPanel extends StatefulWidget {
  final Task task;
  final VoidCallback onClose;
  final VoidCallback onRefresh;

  const HomeTaskDetailPanel({
    super.key,
    required this.task,
    required this.onClose,
    required this.onRefresh,
  });

  @override
  State<HomeTaskDetailPanel> createState() => _HomeTaskDetailPanelState();
}

class _HomeTaskDetailPanelState extends State<HomeTaskDetailPanel> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _repeatIntervalController;

  late String _priority;
  late String _taskType;
  late String _repeatType;
  late int _repeatInterval;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  DateTime? _reminderAt;
  int? _systemTagId;
  final Set<int> _selectedWeekdays = {};
  List<Map<String, dynamic>> _systemTags = [];
  bool _systemTagsLoaded = false;
  bool _isSaving = false;
  bool _moreExpanded = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descController = TextEditingController(
      text: widget.task.description ?? '',
    );
    _priority = widget.task.priority;
    _taskType = widget.task.taskType;
    _dueDate = widget.task.dueDate;
    _dueTime =
        widget.task.dueTime != null
            ? TimeOfDay(
              hour: int.parse(widget.task.dueTime!.split(':')[0]),
              minute: int.parse(widget.task.dueTime!.split(':')[1]),
            )
            : null;
    _repeatType = widget.task.repeatType;
    _repeatInterval = widget.task.repeatInterval;
    _repeatIntervalController = TextEditingController(
      text: _repeatInterval.toString(),
    );
    if (widget.task.repeatDays.isNotEmpty) {
      _selectedWeekdays.addAll(
        widget.task.repeatDays
            .split(',')
            .map((s) => int.tryParse(s.trim()) ?? 0)
            .where((day) => day > 0),
      );
    }
    _reminderAt = widget.task.reminderAt;
    _systemTagId = widget.task.systemTagId;
    _loadSystemTags();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _repeatIntervalController.dispose();
    super.dispose();
  }

  Future<void> _loadSystemTags() async {
    try {
      final tags = await ApiService.getSystemTags();
      if (mounted) {
        setState(() {
          _systemTags = tags;
          _systemTagsLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _systemTagsLoaded = true);
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final weekdays = _selectedWeekdays.toList()..sort();
      await DataService().updateTask(
        localId: widget.task.id,
        serverId: null,
        listId: widget.task.listId,
        title: _titleController.text.trim(),
        description:
            _descController.text.trim().isEmpty
                ? null
                : _descController.text.trim(),
        priority: _priority,
        dueDate: _dueDate,
        dueTime:
            _dueTime != null
                ? '${_dueTime!.hour.toString().padLeft(2, "0")}:${_dueTime!.minute.toString().padLeft(2, "0")}'
                : null,
        taskType: _taskType,
        repeatType: _repeatType,
        repeatInterval: _repeatInterval,
        repeatDays: weekdays.isNotEmpty ? weekdays.join(',') : '',
        reminderAt: _reminderAt,
        reminderAdvanceMinutes: widget.task.reminderAdvanceMinutes,
        systemTagId: _systemTagId,
      );
      widget.onRefresh();
      if (mounted) widget.onClose();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        FxNotice.showContent(context, Text('保存失败: $e'));
      }
    }
  }

  Future<void> _deleteTask() async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '删除任务',
      content: '确定删除「${widget.task.title}」吗？',
      confirmText: '删除',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await DataService().deleteTask(widget.task.id, null);
      widget.onRefresh();
      if (mounted) widget.onClose();
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(context, Text('删除失败: $e'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text(
                  '任务详情',
                  style: TextStyle(
                    fontSize: SlowlightTypography.buttonSize,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                FxIconButton(
                  icon: Icons.close,
                  iconSize: 20,
                  onPressed: widget.onClose,
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          const FxSeparator.horizontal(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextBlock(),
                  const SizedBox(height: 20),
                  _buildPrimaryProperties(),
                  const SizedBox(height: 16),
                  _buildMoreSettings(),
                  const SizedBox(height: 20),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBlock() {
    final theme = Theme.of(context);
    return Column(
      children: [
        FxInput(
          controller: _titleController,
          placeholder: '任务标题',
          style: const TextStyle(
            fontSize: SlowlightTypography.sectionTitleSize,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
          maxLines: null,
        ),
        const SizedBox(height: 10),
        FxInput(
          controller: _descController,
          placeholder: '添加描述...',
          placeholderStyle: TextStyle(color: theme.colorScheme.outline),
          style: TextStyle(
            fontSize: SlowlightTypography.buttonSize,
            height: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: null,
        ),
      ],
    );
  }

  Widget _buildPrimaryProperties() {
    return Column(
      children: [
        _propertyRow(
          icon: Icons.folder_outlined,
          label: '清单',
          value: widget.task.list?.name ?? '当前清单',
          muted: widget.task.list == null,
          trailing: const SizedBox(width: 18),
        ),
        _dateMenu(),
        _timeMenu(),
        _priorityMenu(),
        if (_systemTagsLoaded && _systemTags.isNotEmpty) _systemTagMenu(),
      ],
    );
  }

  Widget _buildMoreSettings() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(SlowlightRadius.md),
      ),
      child: Column(
        children: [
          FxInkWell(
            onTap: () => setState(() => _moreExpanded = !_moreExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '更多设置',
                    style: TextStyle(
                      fontSize: SlowlightTypography.buttonSize,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _moreExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_moreExpanded) ...[
            FxSeparator.horizontal(
              height: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                children: [
                  _taskTypeMenu(),
                  _repeatMenu(),
                  if (_repeatType == 'weekly') _weekdayPicker(),
                  if (_repeatType != 'none') _repeatIntervalInput(),
                  _reminderPicker(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxButton(
          label: _isSaving ? '保存中...' : '保存',
          onPressed: _isSaving ? null : _save,
        ),
        const SizedBox(height: 12),
        FxButton(
          label: '删除任务',
          icon: Icons.delete_outline,
          variant: FxButtonVariant.destructive,
          onPressed: _deleteTask,
        ),
      ],
    );
  }

  Widget _propertyRow({
    required IconData icon,
    required String label,
    required String value,
    bool muted = false,
    Color? valueColor,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final color =
        valueColor ??
        (muted ? theme.colorScheme.outline : theme.colorScheme.onSurface);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Icon(
              icon,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: SlowlightTypography.buttonSize,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: SlowlightTypography.buttonSize,
                color: color,
                fontWeight: muted ? FontWeight.w400 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing ??
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.outline,
              ),
        ],
      ),
    );
  }

  Widget _dateMenu() {
    return FxMenu<String>(
      tooltip: '设置日期',
      onSelected: (value) async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        if (value == 'today') setState(() => _dueDate = today);
        if (value == 'tomorrow') {
          setState(() => _dueDate = today.add(const Duration(days: 1)));
        }
        if (value == 'none') setState(() => _dueDate = null);
        if (value == 'custom') {
          final picked = await showFxDatePicker(
            context: context,
            initialDate: _dueDate ?? today,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
          );
          if (picked != null) setState(() => _dueDate = picked);
        }
      },
      itemBuilder:
          (_) => const [
            FxMenuItem(value: 'today', child: Text('今天')),
            FxMenuItem(value: 'tomorrow', child: Text('明天')),
            FxMenuItem(value: 'none', child: Text('无日期')),
            FxMenuItem(value: 'custom', child: Text('选择日期...')),
          ],
      child: _propertyRow(
        icon: Icons.today_outlined,
        label: '日期',
        value: _formatDate(_dueDate),
        muted: _dueDate == null,
      ),
    );
  }

  Widget _timeMenu() {
    return FxMenu<String>(
      tooltip: '设置时间',
      onSelected: (value) async {
        if (value == 'none') {
          setState(() => _dueTime = null);
          return;
        }
        final time = await showFxTimePicker(
          context: context,
          initialTime: _dueTime ?? TimeOfDay.now(),
        );
        if (time != null) setState(() => _dueTime = time);
      },
      itemBuilder:
          (_) => const [
            FxMenuItem(value: 'custom', child: Text('选择时间...')),
            FxMenuItem(value: 'none', child: Text('无时间')),
          ],
      child: _propertyRow(
        icon: Icons.access_time_outlined,
        label: '时间',
        value: _formatTime(_dueTime),
        muted: _dueTime == null,
      ),
    );
  }

  Widget _priorityMenu() {
    return FxMenu<String>(
      tooltip: '设置优先级',
      onSelected: (value) => setState(() => _priority = value),
      itemBuilder:
          (_) =>
              ['none', 'low', 'medium', 'high', 'urgent'].map((priority) {
                return FxMenuItem(
                  value: priority,
                  child: Row(
                    children: [
                      Icon(
                        priority == _priority
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color:
                            priority == _priority
                                ? _priorityColor(priority)
                                : Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Text(_priorityLabel(priority)),
                    ],
                  ),
                );
              }).toList(),
      child: _propertyRow(
        icon: Icons.flag_outlined,
        label: '优先级',
        value: _priorityLabel(_priority),
        valueColor: _priorityColor(_priority),
      ),
    );
  }

  Widget _systemTagMenu() {
    return FxMenu<int?>(
      tooltip: '设置状态标签',
      onSelected: (value) => setState(() => _systemTagId = value),
      itemBuilder:
          (_) => [
            const FxMenuItem<int?>(value: null, child: Text('无状态标签')),
            ..._systemTags.map((tag) {
              final id = tag['id'] as int;
              final name = tag['name'] as String? ?? '';
              final icon = tag['icon'] as String? ?? '';
              return FxMenuItem<int?>(
                value: id,
                child: Row(
                  children: [
                    Text(
                      icon,
                      style: const TextStyle(fontSize: SlowlightTypography.bodySize),
                    ),
                    const SizedBox(width: 8),
                    Text(name),
                  ],
                ),
              );
            }),
          ],
      child: _propertyRow(
        icon: Icons.label_outline,
        label: '状态标签',
        value: _systemTagText(),
        muted: _systemTagId == null,
      ),
    );
  }

  Widget _taskTypeMenu() {
    return FxMenu<String>(
      tooltip: '设置任务类型',
      onSelected: (value) => setState(() => _taskType = value),
      itemBuilder:
          (_) =>
              ['daily', 'branch', 'main', 'explore'].map((type) {
                return FxMenuItem(
                  value: type,
                  child: Text(_taskTypeLabel(type)),
                );
              }).toList(),
      child: _propertyRow(
        icon: Icons.category_outlined,
        label: '任务类型',
        value: _taskTypeLabel(_taskType),
      ),
    );
  }

  Widget _repeatMenu() {
    return FxMenu<String>(
      tooltip: '设置重复',
      onSelected: (value) {
        setState(() {
          _repeatType = value;
          _selectedWeekdays.clear();
        });
      },
      itemBuilder:
          (_) =>
              ['none', 'daily', 'weekly', 'monthly'].map((type) {
                return FxMenuItem(
                  value: type,
                  child: Text(_repeatLabel(type)),
                );
              }).toList(),
      child: _propertyRow(
        icon: Icons.repeat_outlined,
        label: '重复',
        value: _repeatLabel(_repeatType),
        muted: _repeatType == 'none',
      ),
    );
  }

  Widget _weekdayPicker() {
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: 8),
      child: Wrap(
        spacing: 6,
        children:
            days.asMap().entries.map((entry) {
              final day = entry.key + 1;
              final selected = _selectedWeekdays.contains(day);
              return FxChip(
                label: entry.value,
                backgroundColor:
                    selected ? AppTheme.primaryLight : fxSubtleSurface(context),
                foregroundColor:
                    selected
                        ? activePalette.accent
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                borderColor:
                    selected ? activePalette.accent : fxBorder(context),
                borderRadius: 999,
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedWeekdays.remove(day);
                    } else {
                      _selectedWeekdays.add(day);
                    }
                  });
                },
              );
            }).toList(),
      ),
    );
  }

  Widget _repeatIntervalInput() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: 8),
      child: Row(
        children: [
          Text(
            '每',
            style: TextStyle(
              fontSize: SlowlightTypography.buttonSize,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: FxInput(
              controller: _repeatIntervalController,
              keyboardType: TextInputType.number,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null && parsed > 0) _repeatInterval = parsed;
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            {'daily': '天', 'weekly': '周', 'monthly': '月'}[_repeatType] ?? '',
            style: TextStyle(
              fontSize: SlowlightTypography.buttonSize,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reminderPicker() {
    return FxMenu<String>(
      tooltip: '设置提醒',
      onSelected: (value) async {
        if (value == 'none') {
          setState(() => _reminderAt = null);
          return;
        }
        final picked = await showFxDatePicker(
          context: context,
          initialDate: _reminderAt ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked == null) return;
        final time = await showFxTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(_reminderAt ?? DateTime.now()),
        );
        if (time == null) return;
        setState(() {
          _reminderAt = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      },
      itemBuilder:
          (_) => const [
            FxMenuItem(value: 'custom', child: Text('选择提醒时间...')),
            FxMenuItem(value: 'none', child: Text('无提醒')),
          ],
      child: _propertyRow(
        icon: Icons.notifications_outlined,
        label: '提醒',
        value: _formatReminder(_reminderAt),
        muted: _reminderAt == null,
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '无日期';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(date.year, date.month, date.day);
    final diff = due.difference(today).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == -1) return '昨天';
    return '${date.year}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")}';
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '无时间';
    return '${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}';
  }

  String _formatReminder(DateTime? reminder) {
    if (reminder == null) return '无提醒';
    return '${reminder.month}/${reminder.day} ${reminder.hour.toString().padLeft(2, "0")}:${reminder.minute.toString().padLeft(2, "0")}';
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'high':
        return AppTheme.priorityHigh;
      case 'urgent':
        return AppTheme.priorityUrgent;
      case 'medium':
        return AppTheme.priorityMedium;
      case 'low':
        return AppTheme.priorityLow;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'high':
        return '高';
      case 'urgent':
        return '紧急';
      case 'medium':
        return '中';
      case 'low':
        return '低';
      default:
        return '无';
    }
  }

  String _taskTypeLabel(String type) {
    switch (type) {
      case 'branch':
        return '分支';
      case 'main':
        return '主线';
      case 'explore':
        return '探索';
      default:
        return '日常';
    }
  }

  String _repeatLabel(String type) {
    switch (type) {
      case 'daily':
        return '每天';
      case 'weekly':
        return '每周';
      case 'monthly':
        return '每月';
      default:
        return '不重复';
    }
  }

  String _systemTagText() {
    if (_systemTagId == null) return '无状态标签';
    for (final tag in _systemTags) {
      if (tag['id'] == _systemTagId) {
        final icon = tag['icon'] as String? ?? '';
        final name = tag['name'] as String? ?? '';
        return '$icon $name'.trim();
      }
    }
    return '状态标签';
  }
}
