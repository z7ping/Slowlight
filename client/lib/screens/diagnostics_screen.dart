import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/app_error_logger.dart';
import '../services/app_info_service.dart';
import '../ui/fx.dart';

/// 用户可主动查看和导出本机诊断日志；不会自动上传。
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const _sharingChannel =
      MethodChannel('site.z7ping.slowlight/diagnostics');
  late Future<String> _logs;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _logs = AppErrorLogger.instance.readRecent();
  }

  Future<void> _clear() async {
    final confirmed = await FxDialog.confirm(
      context: context,
      title: '清空错误日志',
      content: '确定删除本设备上的当前日志及备份吗？此操作不可恢复。',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await AppErrorLogger.instance.clear();
      if (!mounted) return;
      setState(_reload);
      FxNotice.success(context, '本机日志已清空');
    } catch (_) {
      if (mounted) FxNotice.error(context, '清空日志失败');
    }
  }

  Future<void> _export() async {
    try {
      final contents = await AppErrorLogger.instance.readText();
      if (contents.trim().isEmpty) {
        if (mounted) FxNotice.warning(context, '目前没有可导出的日志');
        return;
      }
      final info = await AppInfoService.instance.load();
      final header = 'Slowlight ${info.version}+${info.buildNumber}\n'
          '系统：${defaultTargetPlatform.name}\n'
          '导出时间：${DateTime.now().toUtc().toIso8601String()}\n';
      if (!kIsWeb && Platform.isAndroid) {
        final file = await AppErrorLogger.instance.createExportFile(
          header: header,
        );
        await _sharingChannel.invokeMethod<void>('shareLog', {
          'path': file.path,
        });
      } else {
        await Clipboard.setData(ClipboardData(text: '$header\n$contents'));
        if (mounted) FxNotice.success(context, '日志已复制，可粘贴保存');
      }
    } catch (_) {
      if (mounted) FxNotice.error(context, '日志导出失败，请稍后再试');
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
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '错误记录仅保存在此设备，默认不会上传。'
                            '日志限制容量并自动轮转，导出前请检查是否包含个人信息。',
                            style: SlowlightTypography.secondary(context)
                                .copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: SlowlightSpacing.md),
                          Wrap(
                            spacing: SlowlightSpacing.md,
                            runSpacing: SlowlightSpacing.md,
                            children: [
                              FxButton(
                                label: '导出日志',
                                icon: LucideIcons.share2,
                                variant: FxButtonVariant.outline,
                                onPressed: _export,
                              ),
                              FxButton(
                                label: '刷新',
                                icon: LucideIcons.refreshCw,
                                variant: FxButtonVariant.outline,
                                onPressed: () => setState(_reload),
                              ),
                              FxButton(
                                label: '清空日志',
                                icon: LucideIcons.trash2,
                                variant: FxButtonVariant.ghost,
                                onPressed: _clear,
                              ),
                            ],
                          ),
                          const SizedBox(height: SlowlightSpacing.md),
                          FutureBuilder<String>(
                            future: _logs,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState != ConnectionState.done) {
                                return const Center(child: FxCircularProgress());
                              }
                              if (snapshot.hasError) {
                                return Text(
                                  '读取日志失败，请重试',
                                  style: SlowlightTypography.secondary(context),
                                );
                              }
                              final text = snapshot.data ?? '';
                              if (text.trim().isEmpty) {
                                return const FxEmptyState(
                                  icon: LucideIcons.fileText,
                                  title: '暂无错误记录',
                                  subtitle: '出现异常后可在此查看或导出',
                                );
                              }
                              return FxCard(
                                expanded: true,
                                child: SelectableText(
                                  text,
                                  style: SlowlightTypography.caption(context),
                                ),
                              );
                            },
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
