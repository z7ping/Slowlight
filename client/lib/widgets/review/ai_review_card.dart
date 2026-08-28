import 'package:flutter/material.dart';

import '../../ai/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';

/// Review 的 AI 增强入口。
///
/// 不自动请求模型，只有用户主动点击才会发送当前 facts/patterns；
/// AiService 内部不依赖 Data Mode，因此 Local Data 也可直接使用 Local/Remote AI。
class AiReviewCard extends StatefulWidget {
  final Map<String, dynamic> review;

  const AiReviewCard({super.key, required this.review});

  @override
  State<AiReviewCard> createState() => _AiReviewCardState();
}

class _AiReviewCardState extends State<AiReviewCard> {
  final _service = AiService();
  bool _enabled = false;
  bool _loadingConfig = true;
  bool _running = false;
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final enabled = await _service.isEnabled();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _loadingConfig = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await _service.reflectOnReview(widget.review);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingConfig || !_enabled) return const SizedBox.shrink();

    return FxCard(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI 解读',
                  style: TextStyle(
                    fontSize: AppTheme.textMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FxButton(
                label: _running ? '解读中…' : (_result == null ? '解读' : '重新解读'),
                size: FxButtonSize.sm,
                variant: FxButtonVariant.secondary,
                onPressed: _running ? null : _run,
              ),
            ],
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Text(_result!, style: const TextStyle(fontSize: AppTheme.textMd, height: 1.6)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                fontSize: AppTheme.textXs,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
