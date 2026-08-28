import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/high_fidelity/high_fidelity_ui.dart';
import 'feishu_screen.dart';

/// 外部平台集成入口页。
class IntegrationScreen extends StatelessWidget {
  const IntegrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('平台集成')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '连接外部平台，让任务和行为记录在你选择的工具中保持同步。',
                    style: TextStyle(
                      fontSize: AppTheme.textSm,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _PlatformCard(
                      icon: Icons.cloud_sync_outlined,
                      name: '飞书多维表格',
                      description: '同步任务、习惯、番茄钟、休息提醒和标签',
                      available: true,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const FeishuScreen()))),
                  const SizedBox(height: 10),
                  _PlatformCard(
                      icon: Icons.article_outlined,
                      name: 'Notion',
                      description: '任务同步、数据库集成',
                      available: false),
                  const SizedBox(height: 20),
                  HfCard(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: .32),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: .12),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Icon(Icons.info_outline,
                          size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('平台连接由你主动配置，数据同步范围可在对应平台页面中查看。',
                              style: TextStyle(
                                  fontSize: AppTheme.textXs,
                                  color: theme.colorScheme.onSurfaceVariant))),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;
  final bool available;
  final VoidCallback? onTap;

  const _PlatformCard(
      {required this.icon,
      required this.name,
      required this.description,
      required this.available,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HfCard(
      onTap: available ? onTap : null,
      padding: EdgeInsets.zero,
      child: Opacity(
        opacity: available ? 1 : .68,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon,
                size: 25,
                color: available
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: AppTheme.textSm,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(description,
                      style: TextStyle(
                          fontSize: AppTheme.textXs,
                          color: theme.colorScheme.onSurfaceVariant)),
                ])),
            if (!available) const HfChip('尚未开放'),
            if (available)
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
