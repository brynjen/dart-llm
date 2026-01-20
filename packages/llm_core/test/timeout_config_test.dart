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
  });
}
