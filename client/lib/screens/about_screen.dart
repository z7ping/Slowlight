import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../ui/widgets/slowlight_logo.dart';
import '../services/app_info_service.dart';
import '../widgets/high_fidelity/hf_page_header.dart';

/// 产品身份与版本信息页。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo> _packageInfo = AppInfoService.instance.load();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const HfPageHeader(title: '关于所行映我'),
            Expanded(
              child: FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: Column(
                            children: [
                              Center(child: SlowlightLogo(size: 92)),
                              const SizedBox(height: 14),
                              Center(
                                child: Text(
                                  '所行映我 · Slowlight',
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  '行为留下轨迹，时间让自我显影',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: AppTheme.textSm,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _info(
                                context,
                                '版本',
                                info == null
                                    ? '读取中…'
                                    : '${info.version}+${info.buildNumber}',
                              ),
                              _info(context, '数据', '本地优先 · 你的记录属于你'),
                              _info(context, '开源许可', '许可证待定'),
                              _link(
                                context,
                                '项目主页',
                                'https://github.com/z7ping/FocusList',
                              ),
                              const SizedBox(height: 28),
                              _dataExplanation(context),
                              const SizedBox(height: 18),
                              Text(
                                '所行映我不是给人打分的教练，而是一面能记住行为和解释的镜子。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: AppTheme.textXs,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataExplanation(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '数据说明',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppTheme.textSm,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          _dataPoint(context, '本地优先', '记录默认保存在本机。'),
          _dataPoint(context, '云端数据', '登录后可使用服务端数据；切换模式不会自动上传本地模式中的记录。'),
          _dataPoint(context, 'AI 服务', '启用后，相关内容会发送到你选择的 AI 服务。'),
          _dataPoint(context, '可控范围', '你可以在设置中调整数据同步和 AI 服务。'),
        ],
      ),
    );
  }

  Widget _dataPoint(BuildContext context, String title, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•  ',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title：',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: AppTheme.textXs,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(BuildContext context, String title, String url) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppTheme.textSm,
              ),
            ),
            const Spacer(),
            Text(
              'GitHub',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: AppTheme.textSm,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new, size: 15, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _info(BuildContext context, String title, String value) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: AppTheme.textSm,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: AppTheme.textSm,
            ),
          ),
        ],
      ),
    );
  }
}
