import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slowlight/services/network_retry.dart';

void main() {
  const policy = NetworkRetryPolicy();

  test('默认上限是四次、十五秒总预算，指数延迟含随机抖动', () {
    expect(policy.maxAttempts, 4);
    expect(policy.maxDuration, const Duration(seconds: 15));
    expect(policy.delayAfter(1, sample: 0.5), const Duration(seconds: 1));
    expect(policy.delayAfter(2, sample: 0.5), const Duration(seconds: 2));
    expect(policy.delayAfter(3, sample: 0.5), const Duration(seconds: 4));
    expect(policy.delayAfter(1, sample: 0), const Duration(milliseconds: 800));
    expect(policy.delayAfter(1, sample: 1), const Duration(milliseconds: 1200));
  });

  test('仅确认未送达的网络请求允许重试', () {
    expect(
      NetworkRetry.requestNotSent(
        http.ClientException('Failed host lookup: example.invalid'),
      ),
      isTrue,
    );
    expect(NetworkRetry.requestNotSent(const SocketException('No route to host')), isTrue);
    expect(NetworkRetry.requestNotSent(http.ClientException('Connection reset')), isFalse);
    expect(NetworkRetry.requestNotSent(TimeoutException('timeout')), isFalse);
    expect(NetworkRetry.requestNotSent(StateError('Failed host lookup')), isFalse);
  });

  test('不会因为连接重置/超时对 OAuth 一次性领取进行重放', () async {
    for (final failure in <Object>[
      http.ClientException('Connection reset by peer'),
      TimeoutException('request timed out'),
    ]) {
      var attempts = 0;
      await expectLater(
        NetworkRetry.run<int>(
          request: () async {
            attempts++;
            throw failure;
          },
          canRetry: NetworkRetry.requestNotSent,
          shouldContinue: () => true,
          delay: (_) async {},
        ),
        throwsA(predicate((error) => identical(error, failure))),
      );
      expect(attempts, 1);
    }
  });

  test('达到总时间上限后不会继续发起请求', () async {
    var attempts = 0;
    await expectLater(
      NetworkRetry.run<int>(
        request: () async {
          attempts++;
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return 1;
        },
        canRetry: NetworkRetry.requestNotSent,
        shouldContinue: () => true,
        policy: const NetworkRetryPolicy(maxDuration: Duration(milliseconds: 20)),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(attempts, 1);
  });

  test('手动取消时忽略正在返回的旧网络错误', () async {
    var active = true;
    var attempts = 0;
    final result = await NetworkRetry.run<int>(
      request: () async {
        attempts++;
        active = false;
        throw http.ClientException('Failed host lookup');
      },
      canRetry: NetworkRetry.requestNotSent,
      shouldContinue: () => active,
      delay: (_) async {},
    );
    expect(result, isNull);
    expect(attempts, 1);
  });
}
