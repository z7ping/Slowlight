import 'package:flutter/material.dart';

import 'habit_tool_screen.dart';

/// 习惯功能兼容入口。
///
/// 习惯的正式 UI 已统一收口到 [HabitToolScreen]，这里仅保留历史路由/调用兼容，
/// 避免继续维护第二套创建、打卡、补卡、编辑和统计实现。
@Deprecated('Use HabitToolScreen instead.')
class HabitScreen extends StatelessWidget {
  const HabitScreen({super.key});

  @override
  Widget build(BuildContext context) => const HabitToolScreen();
}
