import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('TimeoutConfig', () {
    test('default values are correct', () {
      const config = TimeoutConfig.defaultConfig;
      expect(config.connectionTimeout, const Duration(seconds: 10));
      expect(config.readTimeout, const Duration(minutes: 2));
      expect(config.totalTimeout, const Duration(minutes: 10));
      expect(config.readTimeoutForLargePayloads, const Duration(minutes: 5));
      expect(config.largePayloadThreshold, 1024 * 1024);
    });

    test('getReadTimeoutForPayload returns appropriate timeout', () {
      const config = TimeoutConfig.defaultConfig;

      // Small payload
      expect(config.getReadTimeoutForPayload(100), config.readTimeout);

      // Large payload
      expect(
        config.getReadTimeoutForPayload(2 * 1024 * 1024),
        config.readTimeoutForLargePayloads,
      );
    });

    test('getReadTimeoutForPayload with exact threshold value', () {
      const config = TimeoutConfig(
        largePayloadThreshold: 1024 * 1024,
      );

      // Exactly at threshold should use large payload timeout
      expect(
        config.getReadTimeoutForPayload(1024 * 1024),
        config.readTimeoutForLargePayloads,
      );

      // Just below threshold should use normal timeout
      expect(
        config.getReadTimeoutForPayload(1024 * 1024 - 1),
        config.readTimeout,
      );
    });

    test('getReadTimeoutForPayload with zero payload size', () {
      const config = TimeoutConfig.defaultConfig;
      expect(config.getReadTimeoutForPayload(0), config.readTimeout);
    });

    test('getReadTimeoutForPayload with very large payload size', () {
      const config = TimeoutConfig.defaultConfig;
      expect(
        config.getReadTimeoutForPayload(100 * 1024 * 1024), // 100MB
        config.readTimeoutForLargePayloads,
      );
    });

    test('custom threshold values', () {
      const config = TimeoutConfig(
        largePayloadThreshold: 512 * 1024, // 512KB
        readTimeout: Duration(seconds: 30),
        readTimeoutForLargePayloads: Duration(minutes: 2),
      );

      expect(config.getReadTimeoutForPayload(256 * 1024), config.readTimeout);
      expect(
        config.getReadTimeoutForPayload(512 * 1024),
        config.readTimeoutForLargePayloads,
      );
      expect(
        config.getReadTimeoutForPayload(1024 * 1024),
        config.readTimeoutForLargePayloads,
      );
    });
  });
}
