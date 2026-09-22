import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('CacheKeyGenerator.optionsHash', () {
    test('usagePerChunk does not change the cache key', () {
      const off = LLMChatOptions(temperature: 0.2);
      const on = LLMChatOptions(temperature: 0.2, usagePerChunk: true);

      // The flag changes how often vLLM reports the token counter, not what
      // the model generates, so the two requests must share a cache entry.
      expect(
        CacheKeyGenerator.optionsHash(on),
        CacheKeyGenerator.optionsHash(off),
      );
    });

    test('an option that changes the output does change the key', () {
      const a = LLMChatOptions(temperature: 0.2);
      const b = LLMChatOptions(temperature: 0.9);

      expect(
        CacheKeyGenerator.optionsHash(a),
        isNot(CacheKeyGenerator.optionsHash(b)),
      );
    });
  });
}
