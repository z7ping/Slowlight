import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/habit.dart';
import '../models/reflection_entry.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../repositories/habit_repository.dart';
import '../repositories/reflection_repository.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../services/data_mode_manager.dart';
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
typedef SearchSourceLoaders = ({
  Future<List<Task>> Function(String query) tasks,
  Future<List<Habit>> Function() habits,
  Future<List<ReflectionEntry>> Function() reflections,
  Future<List<TodoList>> Function() lists,
});

class SearchScreen extends StatefulWidget {
  final SearchDataLoader? dataLoader;
  // Optional source-level test seam; production still uses existing repositories.
  final SearchSourceLoaders? sourceLoaders;
  /// Only the app shell owns navigation to the canonical habit tool.
  final ValueChanged<Habit>? onOpenHabit;
  /// Observation targets remain distinct from review responses.
  final ValueChanged<ReflectionEntry>? onOpenReflection;

  const SearchScreen({
    super.key,
    this.dataLoader,
    this.sourceLoaders,
    this.onOpenHabit,
    this.onOpenReflection,
  });

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
  List<String> _partialUnavailable = const [];
  String _query = '';
  List<Task> _tasks = const [];
  List<Habit> _habits = const [];
  List<ReflectionEntry> _reflections = const [];
  List<TodoList> _lists = const [];
  int _taskVisible = 20;
  int _habitVisible = 20;
  int _reflectionVisible = 20;

  List<String> _recentSearches = const [];
  String? _recentKey;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecentSearches());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) { if (mounted) _focusNode.requestFocus(); },
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
    // Invalidate pending queries immediately; waiting for the debounce
    // must never allow old results to overwrite a newly typed keyword.
    ++_searchSeq;
    if (value.trim().isEmpty) {
      unawaited(_search(''));
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
    setState(() {
      _loading = true;
      _error = false;
    });
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
        _lists = const [];
        _partialUnavailable = const [];
        _taskVisible = 20;
        _habitVisible = 20;
        _reflectionVisible = 20;
        _loading = false;
      });
      return;
    }

    setState(() {
      if (_query != query) {
        _taskVisible = 20;
        _habitVisible = 20;
        _reflectionVisible = 20;
      }
      _query = query;
      _loading = true;
      _error = false;
    });
    try {
      var unavailable = <String>[];
      final values = await (widget.dataLoader?.call(query) ??
          _loadSearchData(query, onUnavailable: (sources) {
            unavailable = sources;
          }));
      if (!mounted || seq != _searchSeq) return;
      final lower = query.toLowerCase();
      setState(() {
        _tasks = values.tasks;
        // Injected legacy test loaders still supply all habits. Production
        // repository already searched both names and stored log notes.
        _habits = (widget.dataLoader != null || widget.sourceLoaders != null)
            ? values.habits
                .where((habit) => habit.name.toLowerCase().contains(lower))
                .toList(growable: false)
            : values.habits;
        _reflections = values.reflections
            .where((entry) => entry.content.toLowerCase().contains(lower))
            .toList(growable: false);
        _lists = values.lists;
        _partialUnavailable = unavailable;
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
        _partialUnavailable = const [];
        _loading = false;
        _error = true;
      });
    }
  }

  Future<SearchResultData> _loadSearchData(
    String query, {
    required void Function(List<String>) onUnavailable,
  }) async {
    final missing = <String>{};
    final sources = widget.sourceLoaders;
    Future<List<ReflectionEntry>> loadReflections() async {
      if (sources != null) return sources.reflections();
      final result = await ReflectionRepository().searchContent(query);
      if (!result.complete) missing.add('回顾（部分）');
      return result.entries;
    }
    Future<List<Habit>> loadHabits() async {
      if (sources != null) return sources.habits();
      final result = await HabitRepository().searchContent(query);
      if (!result.complete) missing.add('习惯（部分）');
      return result.habits;
    }
    final values = await Future.wait<dynamic>([
      (sources?.tasks(query) ?? DataService().searchTasks(query))
          .catchError((Object _) {
        missing.add('任务');
        return <Task>[];
      }),
      loadHabits().catchError((Object _) {
        missing.add('习惯');
        return <Habit>[];
      }),
      loadReflections().catchError((Object _) {
        missing.add('回顾');
        return <ReflectionEntry>[];
      }),
      (sources?.lists() ?? DataService().getLists())
          .catchError((Object _) {
        missing.add('清单');
        return <TodoList>[];
      }),
    ]);
    if (['任务', '习惯', '回顾', '清单']
        .every(missing.contains)) {
      throw StateError('所有搜索来源均未读取成功');
    }
    onUnavailable(
      ['任务', '习惯', '习惯（部分）', '回顾', '回顾（部分）', '清单']
          .where(missing.contains)
          .toList(growable: false),
    );
    return (
      tasks: values[0] as List<Task>,
      habits: values[1] as List<Habit>,
      reflections: values[2] as List<ReflectionEntry>,
      lists: values[3] as List<TodoList>,
    );
  }

  Future<void> _loadRecentSearches() async {
    try {
      final scope = DataModeManager().isLocal
          ? 'local'
          : 'cloud:${(await AuthService.getUser())?.id ?? 0}';
      // Never share an anonymous cloud history with another account.
      if (scope == 'cloud:0') return;
      final key = 'slowlight.search.recent.v1.$scope';
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _recentKey = key;
        _recentSearches = (prefs.getStringList(key) ?? const <String>[])
            .where((item) => item.trim().isNotEmpty)
            .take(5)
            .toList(growable: true);
      });
    } catch (_) {
      // Search must remain usable if preferences are unavailable.
    }
  }

  Future<void> _persistRecent(String key, List<String> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(key, values);
    } catch (_) {
      // Recent history is optional; failed persistence must not block search.
    }
  }

  void _remember(String query) {
    final key = _recentKey;
    if (key == null) return;
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 5) _recentSearches.removeLast();
    unawaited(_persistRecent(key, List<String>.from(_recentSearches)));
  }

  void _useRecent(String value) {
    _debounce?.cancel();
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
                                        _debounce?.cancel();
                                        _controller.clear();
                                        _search('');
                                        setState(() {});
                                      },
                                      icon: LucideIcons.x,
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
                          if (!_loading && _partialUnavailable.isNotEmpty) ...[
                            FxCard(
                              padding: const EdgeInsets.all(12),
                              expanded: true,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _partialUnavailable.any((source) => source.endsWith('（部分）'))
                                          ? '部分搜索来源尚未完整核对：${_partialUnavailable.join('、')}。以下仅为已载入结果。'
                                          : '部分搜索来源未读取：${_partialUnavailable.join('、')}。以下仅为已载入结果。',
                                      style: SlowlightTypography.secondary(context),
                                    ),
                                  ),
                                  FxButton(
                                    label: '重试',
                                    variant: FxButtonVariant.ghost,
                                    size: FxButtonSize.sm,
                                    onPressed: () => _search(_query),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
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
                            FxEmptyState(
                              icon: LucideIcons.search,
                              title: _partialUnavailable.isEmpty
                                  ? '没有找到相关内容'
                                  : '已读取来源没有匹配结果',
                              subtitle: _partialUnavailable.isEmpty
                                  ? '没有结果也是一种明确答案'
                                  : '其他来源仍待核对，请重试查询',
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
        child: Column(children: _tasks.take(_taskVisible).map(_taskRow).toList()),
      ),
      more: _tasks.length > _taskVisible
          ? FxButton(
              key: const ValueKey('search-task-more'),
              label: '查看更多任务 · 剩余 ${_tasks.length - _taskVisible} 条',
              size: FxButtonSize.sm,
              variant: FxButtonVariant.ghost,
              onPressed: () => setState(() => _taskVisible += 20),
            )
          : null,
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
      onTap: () {
        if (_partialUnavailable.contains('清单')) {
          FxNotice.showContent(
            context,
            const Text('清单暂未读取成功，请重试搜索后打开任务详情'),
          );
          return;
        }
        TaskDetailSheet.show(
          context,
          task: task,
          lists: _lists,
          onChanged: () => _search(_query),
        );
      },
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
          children: _habits.take(_habitVisible).map((habit) {
            return FxInkWell(
              borderRadius: BorderRadius.circular(SlowlightRadius.md),
              onTap: widget.onOpenHabit == null
                  ? null
                  : () => widget.onOpenHabit!(habit),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Text(
                        habit.icon,
                        style: const TextStyle(fontSize: SlowlightIconSize.md),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _highlight(
                              habit.name,
                              _query,
                              style: SlowlightTypography.body(context),
                            ),
                            if (habit.searchNote.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              _highlight(
                                '匹配备注：${habit.searchNote}',
                                _query,
                                style: SlowlightTypography.caption(context),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (habit.streakCount > 0)
                        FxChip(
                          label: '🔥 ${habit.streakCount}',
                          variant: FxChipVariant.secondary,
                        ),
                      if (widget.onOpenHabit != null)
                        const Icon(LucideIcons.chevronRight, size: 16),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      more: _habits.length > _habitVisible
          ? FxButton(
              key: const ValueKey('search-habit-more'),
              label: '查看更多习惯 · 剩余 ${_habits.length - _habitVisible} 条',
              size: FxButtonSize.sm,
              variant: FxButtonVariant.ghost,
              onPressed: () => setState(() => _habitVisible += 20),
            )
          : null,
    );
  }

  Widget _reflectionGroup() {
    final theme = Theme.of(context);
    return _group(
      _partialUnavailable.any((source) => source.startsWith('回顾'))
          ? '回顾与观察 · 已载入 ${_reflections.length} 条'
          : '回顾与观察 · ${_reflections.length} 条',
      FxCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        expanded: true,
        child: Column(
          children:
              _reflections
                  .take(_reflectionVisible)
                  .map(
                    (entry) => FxInkWell(
                      borderRadius: BorderRadius.circular(SlowlightRadius.md),
                      onTap: widget.onOpenReflection == null
                          ? null
                          : () => widget.onOpenReflection!(entry),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
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
                      ),
                    ),
                  )
                  .toList(),
        ),
      ),
      more: _reflections.length > _reflectionVisible
          ? FxButton(
              key: const ValueKey('search-reflection-more'),
              label: '查看更多记录 · 剩余 ${_reflections.length - _reflectionVisible} 条',
              size: FxButtonSize.sm,
              variant: FxButtonVariant.ghost,
              onPressed: () => setState(() => _reflectionVisible += 20),
            )
          : null,
    );
  }

  Widget _group(String label, Widget child, {Widget? more}) {
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
        if (more != null) ...[
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: more),
        ],
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
