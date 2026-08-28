import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../services/lock_screen.dart';
import '../services/reminder_service.dart';
import '../ui/app_theme.dart';

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
    final title = widget.isMicroRest ? '小憩一下' : '休息一下';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isMicroRest ? Icons.self_improvement : Icons.spa,
                color: AppTheme.white54,
                size: 64,
              ),
              const SizedBox(height: 32),
              Text(title, style: TextStyle(color: AppTheme.white70, fontSize: AppTheme.text2Xl)),
              const SizedBox(height: 8),
              Text(_tip, style: TextStyle(color: AppTheme.white38, fontSize: AppTheme.textMd)),
              const SizedBox(height: 32),
              Text(
                '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
                style: TextStyle(color: AppTheme.white, fontSize: 48, fontWeight: FontWeight.w200),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.allowPostpone) ...[
                    ShadButton.ghost(
                      onPressed: _postponeRest,
                      child: const Text('延后 5 分钟', style: TextStyle(color: AppTheme.white54)),
                    ),
                    const SizedBox(width: 24),
                  ],
                  if (!widget.strict) ...[
                    ShadButton.ghost(
                      onPressed: _skipRest,
                      child: const Text('跳过', style: TextStyle(color: AppTheme.white38)),
                    ),
                  ] else ...[
                    Text('🔒 严格模式', style: TextStyle(color: AppTheme.white38, fontSize: AppTheme.textSm)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
