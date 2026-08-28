import 'package:flutter/material.dart';

/// 所行映我统一品牌标识。
///
/// 界面内继续使用高分辨率品牌资源；系统级小图标由各平台专用资源负责，
/// 避免用低分辨率图标反向放大。
class SlowlightLogo extends StatelessWidget {
  final double size;
  final String semanticLabel;

  const SlowlightLogo({
    super.key,
    this.size = 28,
    this.semanticLabel = '所行映我标志',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Image.asset(
        'assets/slowlight_logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
