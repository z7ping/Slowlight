import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../ui/fx.dart';

/// Shared Android task gesture, extracted from the two older task row swipes.
///
/// Right: complete. Left: reveal postpone / more. Vertical scrolling remains
/// owned by the parent list, and regular taps remain owned by [child].
class TaskSwipeRow extends StatefulWidget {
  const TaskSwipeRow({
    super.key,
    required this.child,
    required this.open,
    required this.onOpenChanged,
    required this.onComplete,
    required this.onPostpone,
    required this.onMore,
  });

  final Widget child;
  final bool open;
  final ValueChanged<bool> onOpenChanged;
  final Future<void> Function() onComplete;
  final Future<void> Function() onPostpone;
  final VoidCallback onMore;

  @override
  State<TaskSwipeRow> createState() => _TaskSwipeRowState();
}

class _TaskSwipeRowState extends State<TaskSwipeRow> {
  static const double _actionWidth = 70;
  static const double _revealWidth = _actionWidth * 2;
  static const double _completeThreshold = 82;
  double _offset = 0;
  bool _dragging = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _offset = widget.open ? -_revealWidth : 0;
  }

  @override
  void didUpdateWidget(covariant TaskSwipeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && widget.open != oldWidget.open) {
      _offset = widget.open ? -_revealWidth : 0;
    }
  }

  void _start(DragStartDetails details) {
    if (_running) return;
    setState(() => _dragging = true);
  }

  void _drag(DragUpdateDetails details) {
    if (_running) return;
    setState(() {
      final next = _offset + details.delta.dx;
      // Soft resistance at both ends instead of exposing huge action blocks.
      if (next > 125) {
        _offset = 125 + (next - 125) * .14;
      } else if (next < -_revealWidth) {
        _offset = -_revealWidth + (next + _revealWidth) * .14;
      } else {
        _offset = next;
      }
    });
  }

  void _end(DragEndDetails details) {
    if (_running) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final complete = _offset > _completeThreshold ||
        (velocity > 650 && _offset > 20);
    final reveal = _offset < -_revealWidth * .4 ||
        (velocity < -650 && _offset < -20);

    setState(() {
      _dragging = false;
      _offset = reveal && !complete ? -_revealWidth : 0;
    });
    widget.onOpenChanged(reveal && !complete);
    if (complete) _run(widget.onComplete);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_running) return;
    setState(() {
      _running = true;
      _offset = 0;
    });
    widget.onOpenChanged(false);
    HapticFeedback.lightImpact();
    try {
      await action();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Color foreground,
    required Color background,
    required VoidCallback onTap,
  }) {
    return FxInkWell(
      onTap: _running ? null : onTap,
      child: SizedBox(
        width: _actionWidth,
        child: ColoredBox(
          color: background,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: SlowlightIconSize.sm),
                const SizedBox(height: SlowlightSpacing.xs),
                Text(label,
                    style: SlowlightTypography.caption(context).copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = Color.lerp(
      AppTheme.warning,
      theme.colorScheme.onSurface,
      .32,
    )!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(SlowlightRadius.md),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                Container(
                  width: 125,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: SlowlightSpacing.xxxl),
                  color: AppTheme.success.withValues(alpha: .10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check, size: SlowlightIconSize.sm,
                          color: theme.colorScheme.onSurface),
                      const SizedBox(width: SlowlightSpacing.md),
                      Text('完成',
                          style: SlowlightTypography.caption(context).copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          )),
                    ],
                  ),
                ),
                const Spacer(),
                _action(
                  icon: LucideIcons.clock3,
                  label: '顺延',
                  foreground: warning,
                  background: AppTheme.warning.withValues(alpha: .10),
                  onTap: () => _run(widget.onPostpone),
                ),
                _action(
                  icon: LucideIcons.ellipsis,
                  label: '更多',
                  foreground: theme.colorScheme.onSurfaceVariant,
                  background: fxSubtleSurface(context),
                  onTap: () {
                    setState(() => _offset = 0);
                    widget.onOpenChanged(false);
                    widget.onMore();
                  },
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _start,
              onHorizontalDragUpdate: _drag,
              onHorizontalDragEnd: _end,
              onHorizontalDragCancel: () {
                setState(() {
                  _dragging = false;
                  _offset = widget.open ? -_revealWidth : 0;
                });
              },
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
