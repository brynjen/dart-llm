import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('TimeoutConfig', () {
    test('default values are correct', () {
      final config = TimeoutConfig();
      expect(config.connectionTimeout, Duration(seconds: 10));
      expect(config.readTimeout, Duration(minutes: 2));
      expect(config.totalTimeout, Duration(minutes: 10));
      expect(config.readTimeoutForLargePayloads, Duration(minutes: 5));
      expect(config.largePayloadThreshold, 1024 * 1024);
    });

    test('getReadTimeoutForPayload returns appropriate timeout', () {
      final config = TimeoutConfig();

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
