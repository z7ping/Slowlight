import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/lock_screen.dart';
import '../services/reminder_service.dart';
import '../ui/fx.dart';

/// 全局休息遮罩 — 不依赖任何特定页面，通过 navigatorKey 挂载。
/// 内部监听 ReminderService，状态离开 rest 时自动关闭。
void showRestOverlay(BuildContext context) {
  final service = ReminderService();
  final isMicro = service.state == 'micro_rest';

  showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    transitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) {
      return RestOverlay(
        isMicroRest: isMicro,
        restSeconds: service.remainingSeconds,
        strict: service.isCurrentRestStrict,
        allowPostpone: service.isCurrentRestPostponeAllowed,
      );
    },
  );
}

class RestOverlay extends StatefulWidget {
  final bool isMicroRest;
  final int restSeconds;
  final bool strict;
  final bool allowPostpone;

  const RestOverlay({
    super.key,
    required this.isMicroRest,
    required this.restSeconds,
    required this.strict,
    required this.allowPostpone,
  });

  @override
  State<RestOverlay> createState() => _RestOverlayState();
}

class _RestOverlayState extends State<RestOverlay> {
  late int _remaining;
  Timer? _timer;
  bool _dismissed = false;

  static const List<String> _tips = [
    '站起来走走，活动一下筋骨',
    '看看远处，让眼睛休息一下',
    '喝杯水，补充水分',
    '做几个深呼吸，放松身心',
    '伸展手臂和肩膀',
    '闭目养神，放空大脑',
  ];

  late final String _tip;

  @override
  void initState() {
    super.initState();
    _tip = (List.of(_tips)..shuffle()).first;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _remaining = widget.restSeconds;
    LockScreenManager().updateOverlayCountdown(_remaining);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_dismissed) return;
      if (_remaining <= 0) {
        _timer?.cancel();
        _dismissAndEnd();
        return;
      }
      setState(() => _remaining--);
      LockScreenManager().updateOverlayCountdown(_remaining);
    });
    ReminderService().addListener(_onReminderChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ReminderService().removeListener(_onReminderChanged);
    super.dispose();
  }

  void _onReminderChanged() {
    if (_dismissed) return;
    final s = ReminderService();
    if (s.state != 'micro_rest' && s.state != 'long_rest') {
      // 从外部（托盘重置/停止等）触发了状态变更，自动关闭
      _dismissed = true;
      _timer?.cancel();
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _dismissAndEnd() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    final s = ReminderService();
    if (s.state == 'micro_rest' || s.state == 'long_rest') {
      s.endRest();
    }
  }

  void _skipRest() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    ReminderService().skipRest();
  }

  void _postponeRest() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
    ReminderService().postponeRest();
  }

  @override
  Widget build(BuildContext context) {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    final progress = widget.restSeconds <= 0
        ? 0.0
        : (_remaining / widget.restSeconds).clamp(0.0, 1.0).toDouble();
    final modeLabel = widget.isMicroRest ? 'MICRO BREAK' : 'LONG BREAK';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
              stops: [0, .6, 1],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 14,
                  left: 18,
                  child: Text(
                    modeLabel,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FxProgressRing(
                          value: progress,
                          size: 190,
                          strokeWidth: 8,
                          color: const Color(0xFF4ADE80),
                          backgroundColor: Colors.white.withValues(alpha: .14),
                          semanticsLabel: widget.isMicroRest ? '小憩剩余时间' : '长休息剩余时间',
                          semanticsValue: '$_remaining 秒',
                          child: Container(
                            width: 154,
                            height: 154,
                            decoration: const BoxDecoration(
                              color: Color(0xFF16272E),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _tip,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            height: 1.5,
                          ),
                        ),
                        if (widget.allowPostpone) ...[
                          const SizedBox(height: 14),
                          FxButton(
                            label: '延后 5 分钟',
                            variant: FxButtonVariant.ghost,
                            size: FxButtonSize.sm,
                            foregroundColor: Colors.white54,
                            onPressed: _postponeRest,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 14,
                  child: widget.strict
                      ? const Text(
                          '严格模式 · 不可跳过',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        )
                      : FxButton(
                          label: '跳过',
                          variant: FxButtonVariant.ghost,
                          size: FxButtonSize.sm,
                          foregroundColor: Colors.white38,
                          onPressed: _skipRest,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
