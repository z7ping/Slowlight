import 'package:flutter/material.dart';

import 'fx_section_header.dart';

/// 旧的简单分区标题入口。
///
/// 视觉规则统一委托给 FxSectionHeader，避免维护第二套分区标题字号与颜色。
@Deprecated('Use FxSectionHeader directly for new code')
class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 8),
      child: FxSectionHeader(title: title),
    );
  }
}
