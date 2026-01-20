import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('RetryConfig', () {
    test('default values are correct', () {
      const config = RetryConfig();
      expect(config.maxAttempts, 3);
      expect(config.initialDelay, const Duration(seconds: 1));
      expect(config.maxDelay, const Duration(seconds: 30));
      expect(config.backoffMultiplier, 2.0);
      expect(config.retryableStatusCodes, [429, 500, 502, 503, 504]);
    });

    test('enabled when maxAttempts > 0', () {
      expect(const RetryConfig().enabled, true);
      expect(const RetryConfig(maxAttempts: 0).enabled, false);
    });

    test('getDelayForAttempt calculates exponential backoff', () {
      const config = RetryConfig();

      expect(config.getDelayForAttempt(0), const Duration(seconds: 1));
      expect(config.getDelayForAttempt(1), const Duration(seconds: 2));
      expect(config.getDelayForAttempt(2), const Duration(seconds: 4));
    });

    test('getDelayForAttempt respects maxDelay', () {
      const config = RetryConfig(
        initialDelay: Duration(seconds: 10),
        maxDelay: Duration(seconds: 20),
      );

      final delay = config.getDelayForAttempt(5);
      expect(delay, lessThanOrEqualTo(const Duration(seconds: 20)));
    });

    test('shouldRetryForStatusCode checks retryable codes', () {
      const config = RetryConfig();
      expect(config.shouldRetryForStatusCode(429), true);
      expect(config.shouldRetryForStatusCode(500), true);
      expect(config.shouldRetryForStatusCode(200), false);
      expect(config.shouldRetryForStatusCode(404), false);
    });

    test('getDelayForAttempt with negative numbers', () {
      const config = RetryConfig();
      // Negative should return initialDelay
      expect(config.getDelayForAttempt(-1), config.initialDelay);
      expect(config.getDelayForAttempt(-10), config.initialDelay);
    });

    test('getDelayForAttempt with very large attempt numbers', () {
      const config = RetryConfig(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
      );

      // Very large attempt should be capped at maxDelay
      expect(config.getDelayForAttempt(100), config.maxDelay);
      expect(config.getDelayForAttempt(1000), config.maxDelay);
    });

    test('custom retryable status codes', () {
      const config = RetryConfig(retryableStatusCodes: [408, 503]);

      expect(config.shouldRetryForStatusCode(408), true);
      expect(config.shouldRetryForStatusCode(503), true);
      expect(config.shouldRetryForStatusCode(500), false);
      expect(config.shouldRetryForStatusCode(429), false);
    });

    test('disabled retry (maxAttempts: 0)', () {
      const config = RetryConfig(maxAttempts: 0);
      expect(config.enabled, false);
      expect(config.maxAttempts, 0);
    });

    test('backoff multiplier edge cases', () {
      // Multiplier of 1.0 (no backoff)
      const config1 = RetryConfig(
        initialDelay: Duration(seconds: 1),
        backoffMultiplier: 1.0,
      );
      expect(config1.getDelayForAttempt(0), const Duration(seconds: 1));
      expect(config1.getDelayForAttempt(1), const Duration(seconds: 1));
      expect(config1.getDelayForAttempt(2), const Duration(seconds: 1));

      // Very large multiplier
      const config2 = RetryConfig(
        initialDelay: Duration(milliseconds: 100),
        backoffMultiplier: 10.0,
        maxDelay: Duration(seconds: 1),
      );
      expect(config2.getDelayForAttempt(0), const Duration(milliseconds: 100));
      expect(config2.getDelayForAttempt(1), const Duration(milliseconds: 1000));
      expect(
        config2.getDelayForAttempt(2),
        const Duration(seconds: 1),
      ); // Capped
    });
  });
}
