import 'dart:convert';

/// Local continuity of naturally completed work rounds, not an aggregate of
/// all ended sessions. Manual stops and break sessions must not advance it.
///
/// This value is device-scoped. It is never presented as a cross-device fact;
/// server work_count includes manually ended sessions and cannot replace it.
class PomodoroCycleProgress {
  const PomodoroCycleProgress({
    this.roundsSinceLongBreak = 0,
    this.lastSessionId,
  });

  final int roundsSinceLongBreak;
  final int? lastSessionId;

  static PomodoroCycleProgress decode(String? encoded, {int cycleSize = 4}) {
    if (encoded == null || cycleSize <= 0) return const PomodoroCycleProgress();
    try {
      final value = jsonDecode(encoded);
      if (value is! Map) return const PomodoroCycleProgress();
      final rounds = value['rounds'];
      final id = value['lastSessionId'];
      if (rounds is! int || rounds < 0 || rounds >= cycleSize ||
          (id != null && (id is! int || id <= 0))) {
        return const PomodoroCycleProgress();
      }
      return PomodoroCycleProgress(
        roundsSinceLongBreak: rounds,
        lastSessionId: id as int?,
      );
    } catch (_) {
      return const PomodoroCycleProgress();
    }
  }

  /// Returns the same instance for an already counted session.
  PomodoroCycleProgress advance(int sessionId, {int cycleSize = 4}) {
    if (sessionId <= 0 || cycleSize <= 0 || sessionId == lastSessionId) {
      return this;
    }
    return PomodoroCycleProgress(
      roundsSinceLongBreak: (roundsSinceLongBreak + 1) % cycleSize,
      lastSessionId: sessionId,
    );
  }

  String encode() => jsonEncode({
        'rounds': roundsSinceLongBreak,
        'lastSessionId': lastSessionId,
      });
}
