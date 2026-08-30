import 'package:flutter/material.dart';
import '../../brand.dart';
import '../../theme/app_theme.dart';
import '../../ui/fx.dart';
import '../../services/api_service.dart';

/// 新用户引导流程
class OnboardingGuide extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingGuide({super.key, required this.onComplete});

  /// 显示引导弹窗
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onComplete,
  }) async {
    return FxDialog.raw(
      context: context,
      barrierDismissible: false,
      builder: (_) => OnboardingGuide(onComplete: onComplete),
    );
  }

  @override
  State<OnboardingGuide> createState() => _OnboardingGuideState();
}

class _OnboardingGuideState extends State<OnboardingGuide> {
  int _currentStep = 0;
  final List<String> _selectedTags = [];

  // 预设的四维度标签
  static const List<Map<String, String>> _presetTags = [
    {'name': '身体', 'icon': '🏃', 'color': '#22c55e'},
    {'name': '认知', 'icon': '🧠', 'color': '#3b82f6'},
    {'name': '产出', 'icon': '📦', 'color': '#f97316'},
    {'name': '关系', 'icon': '👥', 'color': '#8b5cf6'},
  ];

  @override
  Widget build(BuildContext context) {
    return FxDialogSurface(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: _currentStep == 0 ? _buildWelcomeStep() : _buildSelectStep(),
      ),
    );
  }

  /// 欢迎步骤
  Widget _buildWelcomeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('👋', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        Text(
          '欢迎使用 $kBrandDisplayName',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          '$kBrandDisplayName 帮你了解自己，而不是管理待办。',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.warmGray500),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                '我们把生活分为四个维度：',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ..._presetTags.map(
                (tag) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tag['icon']!, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(
                        tag['name']!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FxButton(
            label: '开始选择',
            onPressed: () => setState(() => _currentStep = 1),
          ),
        ),
      ],
    );
  }

  /// 选择步骤
  Widget _buildSelectStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '选择你最想关注的维度',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '可以多选，之后随时可以修改',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.warmGray500),
        ),
        const SizedBox(height: 24),
        ..._presetTags.map((tag) => _buildTagOption(tag)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: FxButton(
                label: '跳过',
                variant: FxButtonVariant.secondary,
                onPressed: _completeOnboarding,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FxButton(
                label: '开始使用',
                onPressed: _selectedTags.isEmpty ? null : _completeOnboarding,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTagOption(Map<String, String> tag) {
    final isSelected = _selectedTags.contains(tag['name']);
    final color = Color(
      int.parse(tag['color']!.replaceFirst('#', 'FF'), radix: 16),
    );

    return FxGestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedTags.remove(tag['name']);
          } else {
            _selectedTags.add(tag['name']!);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppTheme.warmBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(tag['icon']!, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tag['name']!,
                    style: TextStyle(
                      fontSize: AppTheme.textLg,
                      fontWeight: FontWeight.w600,
                      color:
                          isSelected
                              ? color
                              : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    _getTagDescription(tag['name']!),
                    style: TextStyle(
                      fontSize: AppTheme.textSm,
                      color: AppTheme.warmGray500,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  String _getTagDescription(String name) {
    switch (name) {
      case '身体':
        return '运动、睡眠、健康';
      case '认知':
        return '学习、专注、思考';
      case '产出':
        return '工作、创作、交付';
      case '关系':
        return '社交、家庭、连接';
      default:
        return '';
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      // 创建选中的系统标签
      for (final tagName in _selectedTags) {
        final tag = _presetTags.firstWhere((t) => t['name'] == tagName);
        await ApiService.createSystemTag(
          name: tag['name']!,
          icon: tag['icon']!,
          color: tag['color']!,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        FxNotice.showContent(context, Text('创建标签失败: $e'));
      }
    }
  }
}
