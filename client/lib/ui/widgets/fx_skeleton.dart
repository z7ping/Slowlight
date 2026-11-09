import 'dart:async';

import 'package:flutter/material.dart';

import '../layout_tokens.dart';
import '../responsive_layout.dart';
import 'fx_card.dart';

/// 静态占位块：只表达几何，不承担独立动画，避免每行一个 Ticker。
class FxSkeleton extends StatelessWidget {
  const FxSkeleton({
    super.key,
    this.width,
    this.height = 12,
    this.radius = SlowlightRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
      );
}

/// 一个区域只使用一个轻微呼吸动画；延迟显示避免快速本地加载闪烁。
class FxSkeletonGroup extends StatefulWidget {
  const FxSkeletonGroup({super.key, required this.child});

  final Widget child;

  @override
  State<FxSkeletonGroup> createState() => _FxSkeletonGroupState();
}

class _FxSkeletonGroupState extends State<FxSkeletonGroup>
    with SingleTickerProviderStateMixin {
  static const _revealDelay = Duration(milliseconds: 150);
  Timer? _revealTimer;
  bool _revealed = false;
  bool _reduceMotion = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _revealTimer = Timer(_revealDelay, () {
      if (!mounted) return;
      setState(() => _revealed = true);
      _syncAnimation();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_revealed && !_reduceMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: '正在加载',
        liveRegion: true,
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _pulse,
            child: widget.child,
            builder: (context, child) => Opacity(
              opacity: !_revealed
                  ? 0
                  : _reduceMotion
                      ? 1
                      : 0.76 + 0.24 * _pulse.value,
              child: child,
            ),
          ),
        ),
      );
}

enum FxSkeletonRowKind { task, habit, timeline }

/// 列表几何由内容类型决定，颜色、圆角、间距均复用 Fx Token。
class FxSkeletonList extends StatelessWidget {
  const FxSkeletonList({
    super.key,
    required this.kind,
    this.count = 3,
  }) : assert(count > 0);

  final FxSkeletonRowKind kind;
  final int count;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(
          count,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: SlowlightSpacing.md),
            child: Row(
              children: [
                if (kind == FxSkeletonRowKind.timeline)
                  const FxSkeleton(width: 42, height: 10)
                else
                  FxSkeleton(
                    width: kind == FxSkeletonRowKind.habit ? 32 : 20,
                    height: kind == FxSkeletonRowKind.habit ? 32 : 20,
                    radius: kind == FxSkeletonRowKind.habit
                        ? SlowlightRadius.md
                        : SlowlightRadius.pill,
                  ),
                const SizedBox(width: SlowlightSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: index.isEven ? 0.78 : 0.62,
                        child: const FxSkeleton(height: 12),
                      ),
                      const SizedBox(height: SlowlightSpacing.md),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: index.isEven ? 0.42 : 0.55,
                        child: const FxSkeleton(height: 9),
                      ),
                    ],
                  ),
                ),
                if (kind != FxSkeletonRowKind.timeline) ...[
                  const SizedBox(width: SlowlightSpacing.xl),
                  FxSkeleton(
                    width: kind == FxSkeletonRowKind.habit ? 52 : 24,
                    height: kind == FxSkeletonRowKind.habit ? 28 : 12,
                    radius: SlowlightRadius.pill,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

enum FxSkeletonPageKind { tasks, habits, review, stats }

/// 首次无缓存读取时使用；既有内容的刷新不得切回这里。
/// 保留真实页面头部和导航，只占位实际尚未知的数据区域。
class FxSkeletonPage extends StatelessWidget {
  const FxSkeletonPage({super.key, required this.kind});

  final FxSkeletonPageKind kind;

  @override
  Widget build(BuildContext context) {
    final isTasks = kind == FxSkeletonPageKind.tasks;
    final isHabits = kind == FxSkeletonPageKind.habits;
    return FxSkeletonGroup(
      child: ListView(
        key: ValueKey('skeleton.${kind.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SlowlightPageInsets.scroll(context, bottom: 88),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isTasks) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              FxSkeleton(width: 142, height: 16),
                              SizedBox(height: SlowlightSpacing.md),
                              FxSkeleton(width: 86, height: 10),
                            ],
                          ),
                        ),
                        const FxSkeleton(
                          width: 64,
                          height: 36,
                          radius: SlowlightRadius.md,
                        ),
                      ],
                    ),
                    const SizedBox(height: SlowlightSpacing.xl),
                    const FxSkeleton(
                      height: 36,
                      radius: SlowlightRadius.md,
                    ),
                    const SizedBox(height: SlowlightSpacing.xl),
                  ],
                  if (isHabits) ...[
                    const FxSkeleton(width: 226, height: 12),
                    const SizedBox(height: SlowlightSpacing.xxxl),
                  ],
                  if (!isTasks && !isHabits) ...[
                    FxCard(
                      padding: const EdgeInsets.all(SlowlightSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FxSkeleton(width: 100, height: 14),
                          const SizedBox(height: SlowlightSpacing.xxxl),
                          Row(
                            children: List.generate(
                              3,
                              (_) => const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: SlowlightSpacing.md),
                                  child: FxSkeleton(height: 40),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SlowlightSpacing.xxxl),
                  ],
                  const FxSkeleton(width: 92, height: 14),
                  const SizedBox(height: SlowlightSpacing.md),
                  FxCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SlowlightSpacing.xl,
                      vertical: SlowlightSpacing.xs,
                    ),
                    child: FxSkeletonList(
                      kind: isHabits
                          ? FxSkeletonRowKind.habit
                          : isTasks
                              ? FxSkeletonRowKind.task
                              : FxSkeletonRowKind.timeline,
                      count: isTasks ? 5 : 3,
                    ),
                  ),
                  if (!isTasks && !isHabits) ...[
                    const SizedBox(height: SlowlightSpacing.xxxl),
                    FxCard(
                      padding: const EdgeInsets.all(SlowlightSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          FxSkeleton(width: 132, height: 14),
                          SizedBox(height: SlowlightSpacing.xxxl),
                          FxSkeleton(height: 72, radius: SlowlightRadius.md),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
