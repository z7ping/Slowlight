import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../main.dart' show authStateNotifier;
import '../services/auth_service.dart';
import '../services/data_mode_manager.dart';
import '../services/migration_service.dart';
import '../ui/fx.dart';
import 'login_screen.dart';

/// Single flow and business state shared by Windows and Android.
class MigrationPreviewDialog extends StatefulWidget {
  const MigrationPreviewDialog({super.key, this.fullScreen = false});
  final bool fullScreen;

  static Future<void> show(BuildContext context) async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: SafeArea(child: MigrationPreviewDialog(fullScreen: true)),
          ),
        ),
      );
    } else {
      await FxDialog.show<void>(
        context: context,
        width: 840,
        barrierDismissible: false,
        child: const MigrationPreviewDialog(),
      );
    }
  }

  @override
  State<MigrationPreviewDialog> createState() => _MigrationPreviewDialogState();
}

enum _MigrationStep { inspect, conflicts, confirm, result }

class _MigrationPreviewDialogState extends State<MigrationPreviewDialog> {
  static const _keys = [
    'lists',
    'tags',
    'system_tags',
    'tasks',
    'subtasks',
    'habits',
    'habit_logs',
    'sessions',
  ];
  static const _labels = [
    '清单',
    '标签',
    '观察标签（旧）',
    '任务',
    '子任务',
    '习惯',
    '打卡记录',
    '专注记录',
  ];
  static const _policies = [
    ('cloud', '保留云端', '复用云端同名实体，关联数据按映射迁移'),
    ('local', '保留本地', '云端原同名项将改名备份，再导入本地记录'),
    ('both', '两份都保留', '本地记录用独立副本名称导入，不覆盖云端'),
  ];

  final _service = MigrationService();
  final _counts = <String, int>{};
  final _choices = <String, String>{};
  MigrationPlan? _plan;
  _MigrationStep _step = _MigrationStep.inspect;
  bool _loading = true;
  bool _authRequired = false;
  bool _executing = false;
  bool _switching = false;
  bool _reconciling = false;
  bool _outcomeUnknown = false;
  bool _showAllMobile = false;
  String? _previewError;
  String? _resultMessage;
  Map<String, dynamic>? _result;
  int? _localReportId;
  int _focused = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _previewError = null;
      _authRequired = false;
      _plan = null;
      _choices.clear();
      _focused = 0;
      _step = _MigrationStep.inspect;
      _counts.clear();
    });
    try {
      final db = await LocalDb().database;
      final queries = [
        'SELECT COUNT(*) AS count FROM lists WHERE deleted_at IS NULL',
        'SELECT COUNT(*) AS count FROM tags',
        'SELECT COUNT(*) AS count FROM system_tags',
        'SELECT COUNT(*) AS count FROM tasks WHERE deleted_at IS NULL',
        'SELECT COUNT(*) AS count FROM subtasks',
        'SELECT COUNT(*) AS count FROM habits WHERE deleted_at IS NULL',
        'SELECT COUNT(*) AS count FROM habit_logs',
        'SELECT COUNT(*) AS count FROM work_sessions',
      ];
      final rows = await Future.wait(queries.map(db.rawQuery));
      if (!mounted || generation != _loadGeneration) return;
      for (var i = 0; i < _keys.length; i++) {
        _counts[_keys[i]] = (rows[i].first['count'] as num?)?.toInt() ?? 0;
      }
      final token = await AuthService.getToken();
      if (!mounted || generation != _loadGeneration) return;
      if (token == null || token.startsWith('local:')) {
        setState(() => _authRequired = true);
        return;
      }
      final plan = await _service.prepare();
      if (!mounted || generation != _loadGeneration) return;
      for (final key in _keys) {
        if (plan.counts[key] is! num) {
          throw const FormatException('云端迁移预览统计不完整');
        }
      }
      setState(() {
        _plan = plan;
        for (final key in _keys) {
          _counts[key] = (plan.counts[key] as num).toInt();
        }
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _previewError = error.toString());
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _conflicts => _plan?.conflicts ?? const [];
  int get _total => _counts.values.fold<int>(0, (s, n) => s + n);
  bool get _ready =>
      _plan != null &&
      !_loading &&
      _previewError == null &&
      _total > 0 &&
      _conflicts.every((c) => _choices.containsKey(_key(c)));
  String _key(Map<String, dynamic> c) => '${c['entity']}:${c['local_id']}';
  String _entity(Object? entity) => switch (entity) {
        'list' => '清单',
        'tag' => '标签',
        'system_tag' => '观察标签（旧）',
        'habit' => '习惯',
        _ => '记录'
      };
  String _policyLabel(String? value) => switch (value) {
        'cloud' => '保留云端',
        'local' => '保留本地',
        'both' => '两份都保留',
        _ => '待处理',
      };

  Widget _button(String label,
          {required VoidCallback? onPressed, bool primary = false}) =>
      FxButton(
        label: label,
        variant: primary ? FxButtonVariant.primary : FxButtonVariant.outline,
        onPressed: onPressed,
      );

  Future<void> _signIn() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => const LoginScreen(preserveDataMode: true)),
    );
    if (mounted) await _load();
  }

  void _next() {
    if (_loading || _executing) return;
    setState(() {
      if (_step == _MigrationStep.inspect && _plan != null && _total > 0) {
        _step = _conflicts.isEmpty
            ? _MigrationStep.confirm
            : _MigrationStep.conflicts;
      } else if (_step == _MigrationStep.conflicts && _ready) {
        _step = _MigrationStep.confirm;
      }
    });
  }

  void _previous() {
    if (_executing || _reconciling) return;
    setState(() {
      _step = switch (_step) {
        _MigrationStep.conflicts => _MigrationStep.inspect,
        _MigrationStep.confirm => _conflicts.isEmpty
            ? _MigrationStep.inspect
            : _MigrationStep.conflicts,
        _ => _step,
      };
    });
  }

  Future<void> _submit() async {
    if (!_ready || _executing || _step != _MigrationStep.confirm) return;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '确认开始迁移？',
      confirmText: '开始迁移',
      content: '按每一项已确认的策略提交；本地原始数据不删除。'
          '提交和本机映射核验完成之前不会切换当前数据源。',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _executing = true);
    try {
      final result = await _service.executePlan(
          _plan!, Map<String, String>.from(_choices));
      if (!mounted) return;
      setState(() {
        _result = result;
        _outcomeUnknown = false;
        _resultMessage = '云端提交与本机 ID 映射均已确认';
        _step = _MigrationStep.result;
      });
    } on MigrationExecutionException catch (error) {
      if (!mounted) return;
      setState(() {
        _localReportId = error.localReportId;
        _outcomeUnknown = true;
        _resultMessage = '执行结果未确认，请查询原始回执后再恢复';
        _step = _MigrationStep.result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewError = error.toString();
        _plan = null;
        _step = _MigrationStep.inspect;
      });
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  Future<void> _reconcile() async {
    if (_reconciling || _localReportId == null) return;
    setState(() => _reconciling = true);
    try {
      final result = await _service.recoverReport(_localReportId!);
      if (!mounted) return;
      setState(() {
        _result = result;
        _outcomeUnknown = false;
        _resultMessage = '已查询到原始云端回执并恢复本机映射';
      });
    } catch (error) {
      if (mounted) {
        FxNotice.showContent(
            context,
            Text(
              '尚不能证明迁移完成；不会再次导入。$error',
            ));
      }
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  Future<void> _switchCloud() async {
    if (_result == null || _outcomeUnknown || _switching) return;
    setState(() => _switching = true);
    try {
      await DataModeManager().setCloud();
      authStateNotifier.value = !authStateNotifier.value;
      if (mounted)
        Navigator.of(context, rootNavigator: !widget.fullScreen).pop();
    } catch (error) {
      if (mounted) FxNotice.showContent(context, Text('切换云端失败：$error'));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _close() {
    if (_executing || _reconciling) return;
    Navigator.of(context, rootNavigator: !widget.fullScreen).pop();
  }

  Widget _header() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: SlowlightSpacing.xl, vertical: SlowlightSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(widget.fullScreen ? '数据迁移' : '迁移本地数据到云端',
                  style: SlowlightTypography.pageTitle(context))),
          if (!_executing)
            FxIconButton(tooltip: '关闭迁移', icon: Icons.close, onPressed: _close),
        ]),
        Text('本地数据始终保留；预览阶段不会写入或删除数据。',
            style: SlowlightTypography.caption(context)
                .copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: SlowlightSpacing.md),
        Row(children: [
          for (var i = 0; i < _MigrationStep.values.length; i++)
            Expanded(
                child: Column(children: [
              Container(
                height: widget.fullScreen ? 4 : 23,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: i <= _step.index
                        ? theme.colorScheme.primary
                        : fxSubtleSurface(context),
                    borderRadius: BorderRadius.circular(SlowlightRadius.sm)),
                child: widget.fullScreen
                    ? null
                    : Text('${i + 1}',
                        style: SlowlightTypography.caption(context).copyWith(
                            color: i <= _step.index
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurfaceVariant)),
              ),
              const SizedBox(height: 4),
              Text(const ['检查数据', '处理冲突', '最终确认', '迁移结果'][i],
                  textAlign: TextAlign.center,
                  style: SlowlightTypography.caption(context)),
            ])),
        ]),
      ]),
    );
  }

  Widget _stats() => LayoutBuilder(builder: (context, size) {
        final scale = MediaQuery.textScalerOf(context)
            .scale(SlowlightTypography.bodySize);
        final columns = scale >= SlowlightTypography.bodySize * 1.3
            ? (widget.fullScreen ? 1 : 2)
            : widget.fullScreen || size.maxWidth < 560
                ? 2
                : 4;
        const gap = SlowlightSpacing.xs;
        final cellWidth = (size.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (var i = 0; i < _keys.length; i++)
            SizedBox(
                width: cellWidth,
                child: Container(
                  padding: const EdgeInsets.all(SlowlightSpacing.md),
                  decoration: BoxDecoration(
                      border: Border.all(color: fxBorder(context)),
                      borderRadius: BorderRadius.circular(SlowlightRadius.md)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _loading || _previewError != null
                                ? '—'
                                : '${_counts[_keys[i]] ?? 0}',
                            style: SlowlightTypography.statValue(context)),
                        Text(_labels[i],
                            style: SlowlightTypography.caption(context)),
                      ]),
                )),
        ]);
      });

  Widget _inspection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本机数据概览', style: SlowlightTypography.cardTitle(context)),
          const SizedBox(height: SlowlightSpacing.xs),
          _stats(),
          const SizedBox(height: SlowlightSpacing.md),
          if (_loading)
            const Center(child: FxCircularProgress())
          else if (_previewError != null) ...[
            Text('迁移预览失败：$_previewError'),
            const SizedBox(height: SlowlightSpacing.xs),
            _button('重新检查', onPressed: _load),
          ] else if (_authRequired) ...[
            const Text('请登录云端并预览；登录不会改变当前本机数据源。'),
            _button('登录云端并预览', onPressed: _signIn, primary: true),
          ] else if (_total == 0)
            const Text('本机没有可迁移数据，无需执行迁移。')
          else ...[
            Text(_conflicts.isEmpty
                ? '云端比对完成，没有同名冲突'
                : '云端比对完成，发现 ${_conflicts.length} 项同名冲突'),
            const SizedBox(height: SlowlightSpacing.xs),
            const Text('同名并不代表字段内容不同；只展示可信的冲突事实。'),
          ],
        ],
      );

  Widget _conflictRow(int i) {
    final c = _conflicts[i];
    return Container(
      color: _focused == i ? fxSubtleSurface(context) : Colors.transparent,
      child: FxInkWell(
        key: ValueKey('migration.conflict.$i'),
        onTap: () => setState(() => _focused = i),
        child: Padding(
          padding: const EdgeInsets.all(SlowlightSpacing.md),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_entity(c['entity'])}：${c['name'] ?? '未命名'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SlowlightTypography.secondary(context)),
            Text(_policyLabel(_choices[_key(c)]),
                style: SlowlightTypography.caption(context)),
          ]),
        ),
      ),
    );
  }

  Widget _policyDetail() {
    final conflict = _conflicts[_focused];
    final key = _key(conflict);
    return Container(
      padding: const EdgeInsets.all(SlowlightSpacing.md),
      decoration: BoxDecoration(
          border: Border.all(color: fxBorder(context)),
          borderRadius: BorderRadius.circular(SlowlightRadius.lg)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_entity(conflict['entity'])}：${conflict['name'] ?? '未命名'}',
            style: SlowlightTypography.cardTitle(context)),
        const SizedBox(height: 4),
        Text(conflict['reason']?.toString() ?? '云端存在同名项',
            style: SlowlightTypography.caption(context)),
        const SizedBox(height: SlowlightSpacing.xs),
        Text('只有同名冲突证据；目前没有可靠的字段级差异。',
            style: SlowlightTypography.caption(context)),
        const SizedBox(height: SlowlightSpacing.md),
        for (final policy in _policies) ...[
          SizedBox(
              width: double.infinity,
              child: _button(
                '${_choices[key] == policy.$1 ? '✓ ' : ''}${policy.$2}',
                primary: _choices[key] == policy.$1,
                onPressed: () => setState(() => _choices[key] = policy.$1),
              )),
          Text(policy.$3, style: SlowlightTypography.caption(context)),
          const SizedBox(height: SlowlightSpacing.xs),
        ],
      ]),
    );
  }

  Future<void> _applyAll() async {
    if (_conflicts.isEmpty) return;
    final value = _choices[_key(_conflicts[_focused])];
    if (value == null) return;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '对全部冲突应用相同策略？',
      confirmText: '应用全部',
      content: '将「${_policyLabel(value)}」应用到全部 ${_conflicts.length} 项，'
          '替换先前逐项选择；不会立即迁移数据。',
    );
    if (confirmed == true && mounted) {
      setState(() {
        for (final conflict in _conflicts) {
          _choices[_key(conflict)] = value;
        }
      });
    }
  }

  Widget _conflictStep() {
    if (_conflicts.isEmpty) return const Text('没有需要处理的同名冲突。');
    final narrow = widget.fullScreen || MediaQuery.sizeOf(context).width < 680;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('处理同名冲突', style: SlowlightTypography.cardTitle(context)),
      Text('${_choices.length} / ${_conflicts.length} 项已处理',
          style: SlowlightTypography.caption(context)),
      const SizedBox(height: SlowlightSpacing.md),
      if (narrow) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _button('上一项',
              onPressed:
                  _focused > 0 ? () => setState(() => _focused--) : null),
          Text('${_focused + 1} / ${_conflicts.length}'),
          _button('下一项',
              onPressed: _focused + 1 < _conflicts.length
                  ? () => setState(() => _focused++)
                  : null),
        ]),
        const SizedBox(height: SlowlightSpacing.xs),
        _policyDetail(),
        const SizedBox(height: SlowlightSpacing.xs),
        _button(_showAllMobile ? '收起全部冲突' : '查看全部冲突',
            onPressed: () => setState(() => _showAllMobile = !_showAllMobile)),
        if (_showAllMobile)
          for (var i = 0; i < _conflicts.length; i++) _conflictRow(i),
      ] else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Container(
            constraints: const BoxConstraints(maxHeight: 320),
            decoration: BoxDecoration(
                border: Border.all(color: fxBorder(context)),
                borderRadius: BorderRadius.circular(SlowlightRadius.lg)),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _conflicts.length,
              itemBuilder: (_, index) => _conflictRow(index),
            ),
          )),
          const SizedBox(width: SlowlightSpacing.md),
          Expanded(child: _policyDetail()),
        ]),
      const SizedBox(height: SlowlightSpacing.md),
      _button('将当前策略应用到全部',
          onPressed: _choices.containsKey(_key(_conflicts[_focused]))
              ? _applyAll
              : null),
    ]);
  }

  Widget _confirmation() {
    int count(String policy) =>
        _choices.values.where((value) => value == policy).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('最终迁移确认', style: SlowlightTypography.cardTitle(context)),
      const SizedBox(height: SlowlightSpacing.md),
      for (final policy in const ['cloud', 'local', 'both'])
        Padding(
            padding: const EdgeInsets.only(bottom: SlowlightSpacing.xs),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_policyLabel(policy)),
                  Text('${count(policy)} 项'),
                ])),
      const SizedBox(height: SlowlightSpacing.md),
      Text('待迁移：$_total 条（八类数据合计）'),
      Text('同名冲突：${_conflicts.length} 项，已确认 ${_choices.length} 项'),
      const SizedBox(height: SlowlightSpacing.md),
      const Text('执行时重新核对预览版本、云端同名记录和当前账号。'
          '本地记录不会删除，失败或结果未知时不切换数据源。'),
      if (_executing) ...[
        const SizedBox(height: SlowlightSpacing.md),
        const Center(child: FxCircularProgress()),
        const Text('正在执行并核对映射，请勿重复提交。'),
      ],
    ]);
  }

  Widget _resultStep() {
    final created = _result?['created'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_outcomeUnknown ? '执行结果未确认' : '迁移已核验完成',
          style: SlowlightTypography.cardTitle(context)),
      const SizedBox(height: SlowlightSpacing.xs),
      Text(_resultMessage ?? ''),
      const SizedBox(height: SlowlightSpacing.md),
      if (_outcomeUnknown) ...[
        const Text('没有证据证明服务端未提交。不能再次执行新的全量迁移。'),
        const SizedBox(height: SlowlightSpacing.md),
        _button(_reconciling ? '正在核对…' : '查询原始回执并恢复映射',
            onPressed: _reconciling ? null : _reconcile, primary: true),
        const SizedBox(height: SlowlightSpacing.xs),
        const Text('找不到回执则维持未确认，不重新导入。'),
      ] else ...[
        const Text('服务端迁移和本机 ID 映射均已完成。'),
        if (created is Map)
          for (var i = 0; i < _keys.length; i++)
            Text('${_labels[i]}：${created[_keys[i]] ?? 0}'),
        const SizedBox(height: SlowlightSpacing.md),
        if (DataModeManager().isLocal)
          _button(_switching ? '正在切换…' : '使用云端数据',
              onPressed: _switching ? null : _switchCloud, primary: true),
      ],
    ]);
  }

  Widget _footer() {
    final canNext = _step == _MigrationStep.inspect
        ? !_loading && _previewError == null && _plan != null && _total > 0
        : _step == _MigrationStep.conflicts && _ready;
    final actions = <Widget>[
      if (_step == _MigrationStep.conflicts || _step == _MigrationStep.confirm)
        _button('上一步', onPressed: _executing ? null : _previous),
      if (_step == _MigrationStep.inspect || _step == _MigrationStep.conflicts)
        _button('下一步', onPressed: canNext ? _next : null, primary: true),
      if (_step == _MigrationStep.confirm)
        _button(_executing ? '迁移中…' : '开始迁移',
            onPressed: _ready && !_executing ? _submit : null, primary: true),
      if (_step == _MigrationStep.result)
        _button('关闭', onPressed: _reconciling ? null : _close),
    ];
    return Container(
      padding: const EdgeInsets.all(SlowlightSpacing.md),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: fxBorder(context)))),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: SlowlightSpacing.xs),
          if (widget.fullScreen) Expanded(child: actions[i]) else actions[i],
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).height - 110;
    final body = Column(
      mainAxisSize: widget.fullScreen ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _header(),
        Flexible(
            child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: SlowlightSpacing.xl, vertical: SlowlightSpacing.md),
          child: switch (_step) {
            _MigrationStep.inspect => _inspection(),
            _MigrationStep.conflicts => _conflictStep(),
            _MigrationStep.confirm => _confirmation(),
            _MigrationStep.result => _resultStep(),
          },
        )),
        _footer(),
      ],
    );
    return PopScope(
      canPop: !_executing && !_reconciling,
      child: widget.fullScreen
          ? SizedBox.expand(child: body)
          : ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: 840, maxHeight: available > 300 ? available : 300),
              child: body),
    );
  }
}
