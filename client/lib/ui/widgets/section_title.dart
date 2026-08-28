import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 统一的分区标题组件
class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppTheme.textMd,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: AppTheme.warmGray500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
