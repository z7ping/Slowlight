import 'dart:math';

/// 一条习惯事实在断网补交、请求重试和跨设备重放中保持同一身份。
String createHabitRecordKey() {
  final random = Random.secure();
  return List<int>.generate(16, (_) => random.nextInt(256))
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}
