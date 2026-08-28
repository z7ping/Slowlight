/// Slowlight 顶层信息架构只有“今天 / 回顾”两条主线。
enum HomePrimarySection { today, review }

/// 其它能力都是工具，不与产品主线平级。
enum HomeToolSection {
  tasks,
  habits,
  quadrant,
  calendar,
  lists,
  observationTags,
  stats,
  weeklyReview,
  timeDistribution,
}

class HomeNavigationState {
  final HomePrimarySection primary;
  final HomeToolSection? tool;

  const HomeNavigationState({
    this.primary = HomePrimarySection.today,
    this.tool,
  });

  const HomeNavigationState.today()
      : primary = HomePrimarySection.today,
        tool = null;

  const HomeNavigationState.review()
      : primary = HomePrimarySection.review,
        tool = null;

  bool get isToday => primary == HomePrimarySection.today && tool == null;
  bool get isReview => primary == HomePrimarySection.review && tool == null;
  bool get isTool => tool != null;

  HomeNavigationState openPrimary(HomePrimarySection value) =>
      HomeNavigationState(primary: value);

  HomeNavigationState openTool(HomeToolSection value) =>
      HomeNavigationState(primary: primary, tool: value);

  HomeNavigationState closeTool() => HomeNavigationState(primary: primary);

  String get title {
    if (tool != null) {
      return switch (tool!) {
        HomeToolSection.tasks => '任务',
        HomeToolSection.habits => '习惯',
        HomeToolSection.quadrant => '四象限',
        HomeToolSection.calendar => '日历',
        HomeToolSection.lists => '清单',
        HomeToolSection.observationTags => '观察标签',
        HomeToolSection.stats => '统计',
        HomeToolSection.weeklyReview => '每周回顾',
        HomeToolSection.timeDistribution => '时间分配',
      };
    }
    return primary == HomePrimarySection.today ? '今天' : '回顾';
  }
}
