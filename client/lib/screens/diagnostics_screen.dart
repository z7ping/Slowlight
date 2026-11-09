import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/app_error_logger.dart';
import '../services/app_info_service.dart';
import '../ui/fx.dart';

/// 诊断记录只在用户主动触发导出时离开本设备。
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, this.logger});

  /// 注入日志源用于独立验证空/错误/有记录状态。
  final AppErrorLogger? logger;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const _sharingChannel =
      MethodChannel('site.z7ping.slowlight/diagnostics');

  late Future<String> _logs;
  late final Future<String> _version;
  bool _initialScrollPending = true;
  final ScrollController _rawScroll = ScrollController();
  bool _followLatest = true;
  bool _exporting = false;
  bool _clearing = false;

  AppErrorLogger get _logger => widget.logger ?? AppErrorLogger.instance;
  bool get _busy => _exporting || _clearing;
  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _rawScroll.addListener(_onRawScrolled);
    _logs = _logger.readRecent();
    _version = _readVersion();
  }

  @override
  void dispose() {
    _rawScroll.dispose();
    super.dispose();
  }

  void _onRawScrolled() {
    if (!_rawScroll.hasClients) return;
    final nearEnd = _rawScroll.position.extentAfter < 48;
    if (nearEnd != _followLatest && mounted) {
      setState(() => _followLatest = nearEnd);
    }
  }

  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_rawScroll.hasClients) return;
      _rawScroll.jumpTo(_rawScroll.position.maxScrollExtent);
    });
  }

  Future<String> _readVersion() async {
    final info = await AppInfoService.instance.load();
    return '${info.version} (${info.buildNumber})';
  }

  Future<void> _reload() async {
    if (_busy) return;
    final pending = _logger.readRecent();
    setState(() {
      _logs = pending;
      _initialScrollPending = _followLatest;
    });
    try {
      await pending;
    } catch (_) {
      // 读取失败由 FutureBuilder 显示，页面保留唯一重试入口。
    }
  }

    Future<void> _clear() async {
    if (_busy) return;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '清空诊断日志',
      content: '确定删除本设备上的当前日志及轮转备份吗？删除后无法恢复。',
      confirmText: '清空日志',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _logger.clear();
      if (!mounted) return;
      setState(() {
        _logs = _logger.readRecent();
        _followLatest = true;
        _initialScrollPending = true;
      });
      FxNotice.success(context, '本机日志已清空');
    } catch (e) {
      if (mounted) {
        FxNotice.errorWithDetails(context, '清空日志失败', e.toString());
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _exporting = true);
    try {
      final contents = await _logger.readText();
      if (contents.trim().isEmpty) {
        if (mounted) FxNotice.warning(context, '目前没有可导出的日志');
        return;
      }
      final info = await AppInfoService.instance.load();
      final header = 'Slowlight ${info.version}+${info.buildNumber}\n'
          '系统：${defaultTargetPlatform.name}\n'
          '导出时间：${DateTime.now().toUtc().toIso8601String()}\n';
      if (_android) {
        final file = await _logger.createExportFile(header: header);
        await _sharingChannel.invokeMethod<void>('shareLog', {'path': file.path});
      } else {
        await Clipboard.setData(ClipboardData(text: '$header\n$contents'));
        if (mounted) FxNotice.success(context, '日志已复制，可粘贴保存');
      }
    } catch (e) {
      if (mounted) {
        FxNotice.errorWithDetails(context, '导出日志失败', e.toString());
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: SlowlightSpacing.md),
        child: Text(
          title,
          style: SlowlightTypography.secondary(context).copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _detailRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: SlowlightTypography.secondary(context)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: SlowlightTypography.caption(context).copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordState({
    required IconData icon,
    required String title,
    required String description,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: SlowlightTypography.secondary(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: SlowlightTypography.secondary(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 12),
                action,
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 固定视口只显示最近部分；完整日志按需读取并分段懒构建。
  Widget _rawLogPanel(String logs) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('诊断日志',
                style: SlowlightTypography.secondary(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FxButton(
              key: const ValueKey('diagnostics.copy_recent'),
              label: '复制',
              icon: LucideIcons.copy,
              size: FxButtonSize.sm,
              variant: FxButtonVariant.ghost,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: logs));
                if (mounted) FxNotice.success(context, '已复制当前显示的日志');
              },
            ),
          ],
        ),
        const SizedBox(height: SlowlightSpacing.md),
        Container(
          key: const ValueKey('diagnostics.raw_viewport'),
          height: _android ? 220 : 280,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(SlowlightRadius.md),
          ),
          child: Scrollbar(
            controller: _rawScroll,
            thumbVisibility: !_android,
            child: SingleChildScrollView(
              controller: _rawScroll,
              padding: const EdgeInsets.all(SlowlightSpacing.md),
              child: SelectableText(
                logs,
                key: const ValueKey('diagnostics.raw_text'),
                style: SlowlightTypography.caption(context).copyWith(
                  fontFamily: 'monospace', height: 1.5,
                ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text('仅显示最近部分，导出包含完整日志',
                style: SlowlightTypography.caption(context).copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (!_followLatest)
              FxButton(
                key: const ValueKey('diagnostics.scroll_latest'),
                label: '跳到最新',
                size: FxButtonSize.sm,
                variant: FxButtonVariant.ghost,
                onPressed: () {
                  setState(() => _followLatest = true);
                  _jumpToLatest();
                },
              ),
            FxButton(
              key: const ValueKey('diagnostics.full_log'),
              label: '查看全文',
              size: FxButtonSize.sm,
              variant: FxButtonVariant.ghost,
              onPressed: _openFullLogs,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openFullLogs() async {
    try {
      final contents = await _logger.readText();
      if (!mounted) return;
      if (contents.trim().isEmpty) {
        FxNotice.warning(context, '目前没有可查看的日志');
        return;
      }
      final chunks = <String>[];
      var buffer = StringBuffer();
      for (final line in contents.split('\n')) {
        if (buffer.length + line.length > 3000 && buffer.isNotEmpty) {
          chunks.add(buffer.toString());
          buffer = StringBuffer();
        }
        buffer.writeln(line);
      }
      if (buffer.isNotEmpty) chunks.add(buffer.toString());
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (pageContext) => Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  FxPageHeader(
                    title: '完整诊断日志',
                    trailing: FxButton(
                      key: const ValueKey('diagnostics.copy_full'),
                      label: '复制全部',
                      size: FxButtonSize.sm,
                      variant: FxButtonVariant.outline,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: contents));
                        if (pageContext.mounted) {
                          FxNotice.success(pageContext, '已复制完整日志');
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: SelectionArea(
                      child: ListView.builder(
                        key: const ValueKey('diagnostics.full_viewport'),
                        padding: const EdgeInsets.all(SlowlightSpacing.md),
                        itemCount: chunks.length,
                        itemBuilder: (context, index) => Text(
                          chunks[index],
                          style: SlowlightTypography.caption(context).copyWith(
                            fontFamily: 'monospace', height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        FxNotice.errorWithDetails(context, '读取完整日志失败', e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const FxPageHeader(title: '应用诊断'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FutureBuilder<String>(
                            future: _logs,
                            builder: (context, snapshot) {
                              final loaded =
                                  snapshot.connectionState == ConnectionState.done;
                              final logs = snapshot.data ?? '';
                              final hasLogs = loaded &&
                                  !snapshot.hasError &&
                                  logs.trim().isNotEmpty;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!loaded)
                                    _recordState(
                                      icon: LucideIcons.fileText,
                                      title: '正在读取诊断记录',
                                      description: '正在检查此设备保存的日志…',
                                    )
                                  else if (snapshot.hasError)
                                    _recordState(
                                      icon: LucideIcons.triangleAlert,
                                      title: '无法读取诊断记录',
                                      description: '日志文件暂时无法访问，请重新尝试。',
                                      action: FxButton(
                                        key: const ValueKey('diagnostics.retry'),
                                        label: '重新读取',
                                        variant: FxButtonVariant.outline,
                                        onPressed: _reload,
                                      ),
                                    )
                                  else if (!hasLogs)
                                    _recordState(
                                      icon: LucideIcons.fileText,
                                      title: '暂无诊断记录',
                                      description:
                                          '本设备没有已保存的诊断日志。遇到异常时可在这里查看。',
                                    )
                                  else ...[
                                    if (_initialScrollPending)
                                      Builder(
                                        builder: (context) {
                                          _initialScrollPending = false;
                                          _jumpToLatest();
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    _rawLogPanel(logs),
                                  ],
                                  const SizedBox(height: SlowlightSpacing.md),
                                  FxSeparator.horizontal(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  const SizedBox(height: SlowlightSpacing.md),
                                  _sectionTitle('诊断信息'),
                                  FutureBuilder<String>(
                                    future: _version,
                                    builder: (context, info) => _detailRow(
                                      '应用版本',
                                      info.hasData
                                          ? info.data!
                                          : info.hasError
                                              ? '暂不可读取'
                                              : '正在读取…',
                                    ),
                                  ),
                                  _detailRow('运行平台', defaultTargetPlatform.name),
                                  _detailRow('日志存储', '仅本设备'),
                                  const SizedBox(height: SlowlightSpacing.md),
                                  FxSeparator.horizontal(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  const SizedBox(height: SlowlightSpacing.md),
                                  _sectionTitle('日志管理'),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FxButton(
                                      key: const ValueKey('diagnostics.export'),
                                      label: _exporting
                                          ? '导出中…'
                                          : _android
                                              ? '导出诊断日志'
                                              : '复制完整日志',
                                      icon: _android
                                          ? LucideIcons.share2
                                          : LucideIcons.copy,
                                      expanded: true,
                                      onPressed: hasLogs && !_busy ? _export : null,
                                    ),
                                  ),
                                  if (hasLogs) ...[
                                    const SizedBox(height: SlowlightSpacing.md),
                                    FxButton(
                                      key: const ValueKey('diagnostics.clear'),
                                      label: _clearing ? '清空中…' : '清空本机日志',
                                      icon: LucideIcons.trash2,
                                      variant: FxButtonVariant.ghost,
                                      onPressed: _busy ? null : _clear,
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: SlowlightSpacing.md),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(LucideIcons.shieldCheck,
                                size: 18, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: SlowlightSpacing.md),
                              Expanded(child: Text(
                                '日志不会自动上传。分享前请检查是否包含个人信息。',
                                style: SlowlightTypography.caption(context).copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                              )),
                            ],
                          ),
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
}
