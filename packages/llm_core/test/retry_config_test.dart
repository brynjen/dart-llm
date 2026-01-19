import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('RetryConfig', () {
    test('default values are correct', () {
      final config = RetryConfig();
      expect(config.maxAttempts, 3);
      expect(config.initialDelay, Duration(seconds: 1));
      expect(config.maxDelay, Duration(seconds: 30));
      expect(config.backoffMultiplier, 2.0);
      expect(config.retryableStatusCodes, [429, 500, 502, 503, 504]);
    });

    test('enabled when maxAttempts > 0', () {
      expect(RetryConfig(maxAttempts: 3).enabled, true);
      expect(RetryConfig(maxAttempts: 0).enabled, false);
    });

    test('getDelayForAttempt calculates exponential backoff', () {
      final config = RetryConfig(
        initialDelay: Duration(seconds: 1),
        backoffMultiplier: 2.0,
      );

      expect(config.getDelayForAttempt(0), Duration(seconds: 1));
      expect(config.getDelayForAttempt(1), Duration(seconds: 2));
      expect(config.getDelayForAttempt(2), Duration(seconds: 4));
    });

    test('getDelayForAttempt respects maxDelay', () {
      final config = RetryConfig(
        initialDelay: Duration(seconds: 10),
        maxDelay: Duration(seconds: 20),
        backoffMultiplier: 2.0,
      );

      final delay = config.getDelayForAttempt(5);
      expect(delay, lessThanOrEqualTo(Duration(seconds: 20)));
    });

    test('shouldRetryForStatusCode checks retryable codes', () {
      final config = RetryConfig();
      expect(config.shouldRetryForStatusCode(429), true);
      expect(config.shouldRetryForStatusCode(500), true);
      expect(config.shouldRetryForStatusCode(200), false);
      expect(config.shouldRetryForStatusCode(404), false);
    });
  });
}
