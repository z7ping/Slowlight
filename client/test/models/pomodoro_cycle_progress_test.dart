import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/pomodoro_cycle_progress.dart';

void main() {
  test('只有确认自然结束的工作轮次进入四轮周期', () {
    var cycle = const PomodoroCycleProgress();
    for (var id = 1; id <= 3; id++) {
      cycle = cycle.advance(id);
      expect(cycle.roundsSinceLongBreak, id);
    }
    // The fourth verified completion yields a long break, then resets.
    cycle = cycle.advance(4);
    expect(cycle.roundsSinceLongBreak, 0);
    cycle = cycle.advance(5);
    expect(cycle.roundsSinceLongBreak, 1);
  });

  test('同一已记录会话不可重复累计，手动停止不调用 advance', () {
    final completed = const PomodoroCycleProgress().advance(101);
    expect(completed.advance(101), same(completed));
    expect(completed.advance(-1), same(completed));
    expect(completed.roundsSinceLongBreak, 1);
    expect(completed.lastSessionId, 101);
  });

  test('重新进入页面时可靠恢复进度和上次会话 ID', () {
    final original = const PomodoroCycleProgress().advance(20).advance(21);
    final restored = PomodoroCycleProgress.decode(original.encode());
    expect(restored.roundsSinceLongBreak, 2);
    expect(restored.lastSessionId, 21);
    expect(restored.advance(21), same(restored));
    expect(restored.advance(22).roundsSinceLongBreak, 3);
  });

  test('损坏、越界的本机轮次不冒充可靠历史', () {
    expect(PomodoroCycleProgress.decode('broken').roundsSinceLongBreak, 0);
    expect(PomodoroCycleProgress.decode('{"rounds":4,"lastSessionId":2}')
        .roundsSinceLongBreak, 0);
    expect(PomodoroCycleProgress.decode('{"rounds":-1,"lastSessionId":2}')
        .roundsSinceLongBreak, 0);
    expect(PomodoroCycleProgress.decode('{"rounds":3,"lastSessionId":0}')
        .roundsSinceLongBreak, 0);
    expect(PomodoroCycleProgress.decode('{}').roundsSinceLongBreak, 0);
  });
}
