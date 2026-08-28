import 'package:flutter/material.dart';

import 'focus_home_screen.dart';

/// 兼容旧 import 的入口壳。
///
/// 实际首页由 [FocusHomeScreen] 承担；旧 HomeScreen 中由多个 String 状态组成的
/// 手写状态机已经移除。顶层产品导航固定为 Today / Review。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const FocusHomeScreen();
}
