import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/habit.dart';
import '../models/reflection_entry.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../repositories/habit_repository.dart';
import '../repositories/reflection_repository.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../widgets/task_detail_sheet.dart';

typedef SearchResultData = ({
  List<Task> tasks,
  List<Habit> habits,
  List<ReflectionEntry> reflections,
  List<TodoList> lists,
});

typedef SearchDataLoader = Future<SearchResultData> Function(String query);

class SearchScreen extends StatefulWidget {
  final SearchDataLoader? dataLoader;

  const SearchScreen({super.key, this.dataLoader});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  int _searchSeq = 0;
  bool _loading = false;
  bool _error = false;
  String _query = '';
  List<Task> _tasks = const [];
  List<Habit> _habits = const [];
  List<ReflectionEntry> _reflections = const [];
  List<TodoList> _lists = const [];

  static final List<String> _recentSearches = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
    setState(() {});
  }

  Future<void> _search(String raw) async {
    final seq = ++_searchSeq;
    final query = raw.trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _query = '';
        _error = false;
        _tasks = const [];
        _habits = const [];
        _reflections = const [];
        _loading = false;
      });
      return;
    }

    setState(() {
      _query = query;
      _loading = true;
      _error = false;
    });
    try {
      final values = await (widget.dataLoader?.call(query) ?? _loadSearchData(query));
      if (!mounted || seq != _searchSeq) return;
      final lower = query.toLowerCase();
      setState(() {
        _tasks = values.tasks;
        _habits = values.habits
            .where((habit) => habit.name.toLowerCase().contains(lower))
            .toList(growable: false);
        _reflections = values.reflections
            .where((entry) => entry.content.toLowerCase().contains(lower))
            .toList(growable: false);
        _lists = values.lists;
        _loading = false;
        _error = false;
      });
      _remember(query);
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _tasks = const [];
        _habits = const [];
        _reflections = const [];
        _lists = const [];
        _loading = false;
        _error = true;
      });
    }
  }

  Future<SearchResultData> _loadSearchData(String query) async {
    final values = await Future.wait<dynamic>([
      DataService().searchTasks(query),
      HabitRepository().getAll(),
      ReflectionRepository().recent(limit: 100),
      DataService().getLists(),
    ]);
    return (
      tasks: values[0] as List<Task>,
      habits: values[1] as List<Habit>,
      reflections: values[2] as List<ReflectionEntry>,
      lists: values[3] as List<TodoList>,
    );
  }

  void _remember(String query) {
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 5) _recentSearches.removeLast();
  }

  void _useRecent(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _search(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const FxPageHeader(title: '搜索'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FxInput(
                            controller: _controller,
                            focusNode: _focusNode,
                            onChanged: _changed,
                            placeholder: '搜索任务、习惯、回顾…',
                            leading: const Icon(LucideIcons.search, size: SlowlightIconSize.lg),
                            trailing:
                                _controller.text.isEmpty
                                    ? null
                                    : FxIconButton(
                                      tooltip: '清空',
                                      onPressed: () {
                                        _controller.clear();
                                        _search('');
                                        setState(() {});
                                      },
                                      icon: LucideIcons.x,
                                    ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_recentSearches.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '最近：',
                                  style: SlowlightTypography.caption(
                                    context,
                                  ).copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                ..._recentSearches.map(
                                  (query) => FxChip(
                                    label: query,
                                    variant:
                                        query == _query
                                            ? FxChipVariant.primary
                                            : FxChipVariant.secondary,
                                    onTap: () => _useRecent(query),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 18),
                          if (_loading)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(36),
                                child: FxCircularProgress(),
                              ),
                            )
                          else if (_query.isEmpty)
                            const FxEmptyState(
                              icon: LucideIcons.search,
                              title: '输入关键词开始搜索',
                              subtitle: '可以查找任务、习惯和你写下的回顾',
                            )
                          else if (_error)
                            FxEmptyState(
                              icon: LucideIcons.triangleAlert,
                              title: '搜索暂时不可用',
                              subtitle: '记录没有丢失，请检查数据服务后重试。',
                              action: FxButton(
                                label: '重试搜索',
                                variant: FxButtonVariant.secondary,
                                onPressed: () => _search(_query),
                              ),
                            )
                          else if (_tasks.isEmpty &&
                              _habits.isEmpty &&
                              _reflections.isEmpty)
                            const FxEmptyState(
                              icon: LucideIcons.search,
                              title: '没有找到相关内容',
                              subtitle: '没有结果也是一种明确答案',
                            )
                          else ...[
                            if (_tasks.isNotEmpty) _taskGroup(),
                            if (_tasks.isNotEmpty &&
                                (_habits.isNotEmpty || _reflections.isNotEmpty))
                              const SizedBox(height: 14),
                            if (_habits.isNotEmpty) _habitGroup(),
                            if (_habits.isNotEmpty && _reflections.isNotEmpty)
                              const SizedBox(height: 14),
                            if (_reflections.isNotEmpty) _reflectionGroup(),
                          ],
                        ],
                      ),
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

  Widget _taskGroup() {
    return _group(
      '任务 · ${_tasks.length} 条',
      FxCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        expanded: true,
        child: Column(children: _tasks.take(20).map(_taskRow).toList()),
      ),
    );
  }

  Widget _taskRow(Task task) {
    final theme = Theme.of(context);
    final meta = <String>[
      if ((task.list?.name ?? '').trim().isNotEmpty) task.list!.name,
      if (task.dueDate != null)
        '${task.dueDate!.month}/${task.dueDate!.day}${task.dueTime == null || task.dueTime!.isEmpty ? '' : ' ${task.dueTime}'}',
    ].join(' · ');
    return FxInkWell(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      onTap:
          () => TaskDetailSheet.show(
            context,
            task: task,
            lists: _lists,
            onChanged: () => _search(_query),
          ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.priorityColor(task.priority),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlight(
                      task.title,
                      _query,
                      style: SlowlightTypography.body(
                        context,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: SlowlightTypography.caption(
                          context,
                        ).copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _habitGroup() {
    return _group(
      '习惯 · ${_habits.length} 条',
      FxCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        expanded: true,
        child: Column(
          children:
              _habits
                  .take(20)
                  .map(
                    (habit) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            habit.icon,
                            style: const TextStyle(fontSize: SlowlightIconSize.md),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: _highlight(
                              habit.name,
                              _query,
                              style: SlowlightTypography.body(context),
                            ),
                          ),
                          if (habit.streakCount > 0)
                            FxChip(
                              label: '🔥 ${habit.streakCount}',
                              variant: FxChipVariant.secondary,
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }

  Widget _reflectionGroup() {
    final theme = Theme.of(context);
    return _group(
      '回顾 · ${_reflections.length} 条',
      FxCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        expanded: true,
        child: Column(
          children:
              _reflections
                  .take(20)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            entry.entryType == 'observation'
                                ? LucideIcons.fileText
                                : LucideIcons.messageCircle,
                            size: SlowlightIconSize.md,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _highlight(
                                  entry.content,
                                  _query,
                                  style: SlowlightTypography.body(context),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${entry.createdAt.month} 月 ${entry.createdAt.day} 日${entry.dimensionKey == null ? '' : ' · #${_dimensionLabel(entry.dimensionKey!)}'}',
                                  style: SlowlightTypography.caption(
                                    context,
                                  ).copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }

  Widget _group(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: SlowlightTypography.caption(context).copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _highlight(String text, String query, {TextStyle? style}) {
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    final start = lower.indexOf(needle);
    if (needle.isEmpty || start < 0) {
      return Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final end = start + query.length;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (start > 0) TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: TextStyle(
              color: activePalette.accent,
              backgroundColor: activePalette.accent.withValues(alpha: .14),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (end < text.length) TextSpan(text: text.substring(end)),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _dimensionLabel(String key) => switch (key) {
    'body' => '身体',
    'cognition' => '认知',
    'output' => '产出',
    'relationship' => '关系',
    _ => key,
  };
}
