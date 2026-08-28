import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../brand.dart';
import '../models/todo_list.dart';
import '../services/auth_service.dart';
import '../services/data_mode_manager.dart';
import '../main.dart' show authStateNotifier;
import '../theme/app_theme.dart';
import '../ui/fx.dart';
import '../ui/widgets/slowlight_logo.dart';
import 'login_screen.dart';
import 'pomodoro_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';

/// 侧边栏导航组件
class HomeDrawer extends StatelessWidget {
  final List<TodoList> lists;
  final int currentNavIndex;
  final String? drawerSubview;
  final Function(int) onNavChanged;
  final Function(String) onDrawerSubviewChanged;
  final VoidCallback onPopDrawer;
  final Future<void> Function() onOpenReminder;

  const HomeDrawer({
    super.key,
    required this.lists,
    required this.currentNavIndex,
    required this.drawerSubview,
    required this.onNavChanged,
    required this.onDrawerSubviewChanged,
    required this.onPopDrawer,
    required this.onOpenReminder,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: _buildMobileDrawerContent(context),
    );
  }

  Widget _buildMobileDrawerContent(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildDrawerHeader(context),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDrawerTab(
                      Icons.home_outlined, Icons.home, '今日', 0, context),
                  _buildDrawerTab(Icons.grid_4x4_outlined, Icons.grid_4x4,
                      '四象限', 1, context),
                  _buildDrawerTab(Icons.self_improvement_outlined,
                      Icons.self_improvement, '习惯', 2, context),
                  _buildDrawerTab(Icons.auto_awesome_outlined,
                      Icons.auto_awesome, '回顾', 3, context),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.warmBorder),
            _buildDrawerItem(
              icon: Icons.tune_outlined,
              title: '清单',
              onTap: () {
                onPopDrawer();
                onDrawerSubviewChanged('list_manage');
              },
            ),
            _buildDrawerItem(
              icon: Icons.label_outlined,
              title: '标签',
              onTap: () {
                onPopDrawer();
                onDrawerSubviewChanged('system_tag');
              },
            ),
            _buildDrawerItem(
              icon: Icons.timer_outlined,
              title: '番茄钟',
              onTap: () {
                onPopDrawer();
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PomodoroScreen()));
              },
            ),
            if (!kIsWeb &&
                (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
              _buildDrawerItem(
                icon: Icons.self_improvement,
                title: '休息提醒',
                onTap: () {
                  onPopDrawer();
                  onOpenReminder();
                },
              ),
            _buildDrawerItem(
              icon: Icons.settings_outlined,
              title: '设置',
              onTap: () {
                onPopDrawer();
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            _buildDrawerItem(
              icon: Icons.help_outline,
              title: '关于',
              onTap: () {
                onPopDrawer();
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()));
              },
            ),
            const SizedBox(height: 24),
            Divider(height: 1),
            _buildDrawerItem(
              icon: Icons.logout,
              title: '退出登录',
              iconColor: AppTheme.priorityHigh,
              textColor: AppTheme.priorityHigh,
              onTap: () async {
                onPopDrawer();
                final confirmed = await FxDialog.confirm(
                  context: context,
                  title: '确认退出',
                  content: '确定要退出登录吗？',
                  confirmText: '退出',
                );
                if (confirmed != true) return;
                await AuthService.logout();
                await DataModeManager().setCloud();
                authStateNotifier.value = false;
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          // 头像
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.person_outline,
              color: AppTheme.primary,
              size: 24,
            ),
          ),
          SizedBox(width: 12),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kBrandDisplayName,
                  style: TextStyle(
                    fontSize: AppTheme.textLg,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textColor(context),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '${lists.length} 个清单',
                  style: TextStyle(
                    fontSize: AppTheme.textMd,
                    height: 1.5,
                    color: AppTheme.warmGray500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerTab(IconData icon, IconData activeIcon, String label,
      int index, BuildContext context) {
    final isActive = currentNavIndex == index;
    return FxInkWell(
      onTap: () => onNavChanged(index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon,
                size: 20,
                color: isActive ? AppTheme.primary : AppTheme.warmGray500),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: AppTheme.textXs,
                  height: 1.2,
                  color: isActive ? AppTheme.primary : AppTheme.warmGray500,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
    bool isSelected = false,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border(left: BorderSide(color: AppTheme.primary, width: 3))
            : null,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          size: 20,
          color: iconColor ??
              (isSelected ? AppTheme.primary : AppTheme.warmGray500),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: AppTheme.textMd,
            height: 1.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: textColor ??
                (isSelected ? AppTheme.primary : AppTheme.warmGray500),
          ),
        ),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minLeadingWidth: 20,
        horizontalTitleGap: 12,
        onTap: onTap,
      ),
    );
  }
}

/// 桌面端侧边栏组件
class HomeDesktopSidebar extends StatelessWidget {
  final int currentNavIndex;
  final Function(int) onNavChanged;
  final Function(String) onDrawerSubviewChanged;
  final Future<void> Function() onOpenReminder;

  const HomeDesktopSidebar({
    super.key,
    required this.currentNavIndex,
    required this.onNavChanged,
    required this.onDrawerSubviewChanged,
    required this.onOpenReminder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.warmWhite,
      child: Column(
        children: [
          // 顶部：App 名称（紧凑）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const SlowlightLogo(size: 24),
                const SizedBox(width: 8),
                Text(kBrandDisplayName,
                    style: TextStyle(
                      fontSize: AppTheme.textLg,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textColor(context),
                    )),
              ],
            ),
          ),

          // Tab 切换
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildDrawerTab(
                    Icons.home_outlined, Icons.home, '今日', 0, context),
                _buildDrawerTab(
                    Icons.grid_4x4_outlined, Icons.grid_4x4, '四象限', 1, context),
                _buildDrawerTab(Icons.self_improvement_outlined,
                    Icons.self_improvement, '习惯', 2, context),
                _buildDrawerTab(Icons.auto_awesome_outlined, Icons.auto_awesome,
                    '回顾', 3, context),
              ],
            ),
          ),

          Divider(height: 1, color: AppTheme.warmBorder),

          // 中间：可滚动菜单项
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _buildDrawerItem(
                    icon: Icons.tune_outlined,
                    title: '清单',
                    onTap: () => onDrawerSubviewChanged('list_manage'),
                  ),
                  _buildDrawerItem(
                    icon: Icons.label_outlined,
                    title: '标签',
                    onTap: () => onDrawerSubviewChanged('system_tag'),
                  ),
                  _buildDrawerItem(
                    icon: Icons.timer_outlined,
                    title: '番茄钟',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PomodoroScreen())),
                  ),
                  if (!kIsWeb &&
                      (Platform.isWindows ||
                          Platform.isLinux ||
                          Platform.isMacOS))
                    _buildDrawerItem(
                      icon: Icons.self_improvement,
                      title: '休息提醒',
                      onTap: () => onOpenReminder(),
                    ),
                  _buildDrawerItem(
                    icon: Icons.settings_outlined,
                    title: '设置',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
            ),
          ),

          Divider(height: 1, color: AppTheme.warmBorder),

          // 底部：退出登录（钉在左下角）
          _buildDrawerItem(
            icon: Icons.logout,
            title: '退出登录',
            iconColor: AppTheme.priorityHigh,
            textColor: AppTheme.priorityHigh,
            onTap: () async {
              final confirmed = await FxDialog.confirm(
                context: context,
                title: '确认退出',
                content: '确定要退出登录吗？',
                confirmText: '退出',
              );
              if (confirmed != true) return;
              await AuthService.logout();
              await DataModeManager().setCloud();
              authStateNotifier.value = false;
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDrawerTab(IconData icon, IconData activeIcon, String label,
      int index, BuildContext context) {
    final isActive = currentNavIndex == index;
    return FxInkWell(
      onTap: () => onNavChanged(index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon,
                size: 20,
                color: isActive ? AppTheme.primary : AppTheme.warmGray500),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: AppTheme.textXs,
                  height: 1.2,
                  color: isActive ? AppTheme.primary : AppTheme.warmGray500,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
    bool isSelected = false,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isSelected
            ? Border(left: BorderSide(color: AppTheme.primary, width: 3))
            : null,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          size: 20,
          color: iconColor ??
              (isSelected ? AppTheme.primary : AppTheme.warmGray500),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: AppTheme.textMd,
            height: 1.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: textColor ??
                (isSelected ? AppTheme.primary : AppTheme.warmGray500),
          ),
        ),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minLeadingWidth: 20,
        horizontalTitleGap: 12,
        onTap: onTap,
      ),
    );
  }
}
