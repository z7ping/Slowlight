import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// 可按接口显式启用的网络重试策略，不自动重放写操作。
class NetworkRetryPolicy {
  const NetworkRetryPolicy({
    this.maxAttempts = 4,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDuration = const Duration(seconds: 15),
    this.jitterRatio = 0.2,
  })  : assert(maxAttempts > 0),
        assert(!initialDelay.isNegative),
        assert(maxDuration > Duration.zero),
        assert(jitterRatio >= 0 && jitterRatio <= 1);

  /// 含首次请求的总尝试次数。
  final int maxAttempts;
  final Duration initialDelay;
  /// 全部请求和等待共享的时间上限。
  final Duration maxDuration;
  /// 防止大量客户端同一时刻重试，默认在基础延时 ±20% 波动。
  final double jitterRatio;

  Duration delayAfter(int completedAttempt, {double? sample}) {
    assert(completedAttempt > 0);
    final multiplier = 1 << min(completedAttempt - 1, 20);
    final unit = (sample ?? Random().nextDouble()).clamp(0.0, 1.0);
    final milliseconds = (initialDelay.inMilliseconds *
            multiplier *
            (1 - jitterRatio + jitterRatio * 2 * unit))
        .round();
    return Duration(milliseconds: milliseconds);
  }
}

abstract final class NetworkRetry {
  /// 仅对明确“未送达服务端”的传输失败自动重试。
  ///
  /// 不允许把超时和连接重置当成安全重试依据：服务器可能已经完成
  /// POST 并消费一次性凭据/写入数据，客户端却未收到响应。
  static bool requestNotSent(Object error) {
    if (error is! SocketException && error is! http.ClientException) {
      return false;
    }
    final message = error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('no route to host');
  }

  static bool isNetworkFailure(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return true;
    }
    return false;
  }

  /// 由业务端显式传入是否可重试，不能依赖 HTTP method 自动判断
  /// OAuth 一次性领取等非幂等端点。
  static Future<T?> run<T>({
    required Future<T> Function() request,
    required bool Function(Object) canRetry,
    required bool Function() shouldContinue,
    NetworkRetryPolicy policy = const NetworkRetryPolicy(),
    Future<void> Function(Duration)? delay,
    double Function()? randomUnit,
  }) async {
    final elapsed = Stopwatch()..start();
    for (var attempt = 1; attempt <= policy.maxAttempts; attempt++) {
      if (!shouldContinue()) return null;
      final remaining = policy.maxDuration - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('请求已超过最大重试时长');
      }
      try {
        return await request().timeout(remaining);
      } catch (error) {
        // 用户已主动取消时不再弹出过期的网络错误。
        if (!shouldContinue()) return null;
        if (!canRetry(error) || attempt == policy.maxAttempts) rethrow;
        if (!shouldContinue()) return null;
        final backoff = policy.delayAfter(
          attempt,
          sample: randomUnit?.call(),
        );
        if (backoff >= policy.maxDuration - elapsed.elapsed) rethrow;
        await (delay?.call(backoff) ?? Future<void>.delayed(backoff));
      }
    }
    return null;
  }
}
