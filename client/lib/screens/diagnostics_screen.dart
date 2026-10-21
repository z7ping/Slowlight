import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/app_error_logger.dart';
import '../services/app_info_service.dart';
import '../ui/fx.dart';

/// 错误记录只在用户主动触发导出时离开本设备。
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
  bool _showRawLogs = false;
  bool _exporting = false;
  bool _clearing = false;

  AppErrorLogger get _logger => widget.logger ?? AppErrorLogger.instance;
  bool get _busy => _exporting || _clearing;
  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _logs = _logger.readRecent();
    _version = _readVersion();
  }

  Future<String> _readVersion() async {
    final info = await AppInfoService.instance.load();
    return '${info.version} (${info.buildNumber})';
  }

  void _reload() {
    if (_busy) return;
    setState(() => _logs = _logger.readRecent());
  }

  Future<void> _clear() async {
    if (_busy) return;
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '清空错误日志',
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
        _showRawLogs = false;
        _logs = _logger.readRecent();
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
      padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.md),
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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(SlowlightRadius.md),
          ),
          child: Icon(icon, size: 24, color: theme.colorScheme.onSurfaceVariant),
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

  Widget _rawLogPanel(String logs) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FxInkWell(
          key: const ValueKey('diagnostics.raw_toggle'),
          onTap: () => setState(() => _showRawLogs = !_showRawLogs),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Text('日志原文',
                      style: SlowlightTypography.secondary(context).copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                ),
                Text(
                  _showRawLogs ? '收起' : '展开',
                  style: SlowlightTypography.caption(context).copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _showRawLogs ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_showRawLogs)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SlowlightSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(SlowlightRadius.md),
            ),
            child: SelectableText(
              logs,
              key: const ValueKey('diagnostics.raw_text'),
              style: SlowlightTypography.caption(context),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            FxPageHeader(
              title: '应用诊断',
              actionIcon: LucideIcons.refreshCw,
              actionTooltip: '刷新错误记录',
              onAction: _busy ? null : _reload,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle('错误记录'),
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
                                      title: '正在读取错误记录',
                                      description: '正在检查此设备保存的日志…',
                                    )
                                  else if (snapshot.hasError)
                                    _recordState(
                                      icon: LucideIcons.triangleAlert,
                                      title: '无法读取错误记录',
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
                                      title: '暂无错误记录',
                                      description:
                                          '本设备没有已保存的错误日志。遇到异常时可在这里查看。',
                                    )
                                  else ...[
                                    _recordState(
                                      icon: LucideIcons.fileText,
                                      title: '已有错误记录',
                                      description:
                                          '可查看日志原文，或导出完整记录用于排查。',
                                    ),
                                    const SizedBox(height: SlowlightSpacing.md),
                                    _rawLogPanel(logs),
                                  ],
                                  const SizedBox(height: SlowlightSpacing.xl),
                                  FxSeparator.horizontal(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  const SizedBox(height: SlowlightSpacing.xl),
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
                                  const SizedBox(height: SlowlightSpacing.xl),
                                  FxSeparator.horizontal(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                  const SizedBox(height: SlowlightSpacing.xl),
                                  _sectionTitle('日志管理'),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('导出错误日志',
                                              style: SlowlightTypography.secondary(context)),
                                            const SizedBox(height: 4),
                                            Text(
                                              hasLogs
                                                  ? _android
                                                      ? '使用系统分享发送完整日志'
                                                      : '复制完整日志到剪贴板'
                                                  : '当前没有可导出的记录',
                                              style: SlowlightTypography.caption(context).copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      FxButton(
                                        key: const ValueKey('diagnostics.export'),
                                        label: _exporting
                                            ? '导出中…'
                                            : _android
                                                ? '导出'
                                                : '复制',
                                        size: FxButtonSize.sm,
                                        onPressed: hasLogs && !_busy ? _export : null,
                                      ),
                                    ],
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
                          const SizedBox(height: SlowlightSpacing.xl),
                          Container(
                            padding: const EdgeInsets.all(SlowlightSpacing.md),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(SlowlightRadius.md),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(LucideIcons.shieldCheck,
                                  size: 18, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '错误日志默认不会上传。主动分享前，请检查其中是否包含个人信息。',
                                    style: SlowlightTypography.caption(context).copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
