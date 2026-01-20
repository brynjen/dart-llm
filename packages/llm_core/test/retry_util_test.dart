import 'dart:async';

import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('RetryUtil', () {
    test('executes operation without retry when config is null', () async {
      var callCount = 0;
      final result = await RetryUtil.executeWithRetry(
        operation: () async {
          callCount++;
          return 'success';
        },
      );

      expect(result, 'success');
      expect(callCount, 1);
    });

    test('executes operation without retry when disabled', () async {
      var callCount = 0;
      final result = await RetryUtil.executeWithRetry(
        operation: () async {
          callCount++;
          return 'success';
        },
        config: const RetryConfig(maxAttempts: 0),
      );

      expect(result, 'success');
      expect(callCount, 1);
    });

    test('retries on retryable errors', () async {
      var callCount = 0;
      const error = LLMApiException('Server error', statusCode: 500);

      await expectLater(
        RetryUtil.executeWithRetry(
          operation: () async {
            callCount++;
            if (callCount < 3) {
              throw error;
            }
            return 'success';
          },
          config: const RetryConfig(initialDelay: Duration(milliseconds: 10)),
        ),
        completion('success'),
      );

      expect(callCount, 3);
    });

    test('stops retrying after max attempts', () async {
      var callCount = 0;
      const error = LLMApiException('Server error', statusCode: 500);

      await expectLater(
        RetryUtil.executeWithRetry(
          operation: () async {
            callCount++;
            throw error;
          },
          config: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration(milliseconds: 10),
          ),
        ),
        throwsA(isA<LLMApiException>()),
      );

      expect(callCount, 3); // Initial + 2 retries
    });

    test('does not retry on non-retryable errors', () async {
      var callCount = 0;
      const error = LLMApiException('Client error', statusCode: 400);

      await expectLater(
        RetryUtil.executeWithRetry(
          operation: () async {
            callCount++;
            throw error;
          },
          config: const RetryConfig(),
        ),
        throwsA(isA<LLMApiException>()),
      );

      expect(callCount, 1); // No retries for 400
    });

    test('retries on timeout exceptions', () async {
      var callCount = 0;

      await expectLater(
        RetryUtil.executeWithRetry(
          operation: () async {
            callCount++;
            if (callCount < 2) {
              throw TimeoutException('Timeout');
            }
            return 'success';
          },
          config: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration(milliseconds: 10),
          ),
        ),
        completion('success'),
      );

      expect(callCount, 2);
    });
  });
}
