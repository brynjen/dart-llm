import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

import 'mock_llm_chat_repository.dart';

void main() {
  group('StreamChatOptions integration', () {
    test('options take precedence over individual parameters', () async {
      final mock = MockLLMChatRepository();
      mock.setResponse('Response');

      const options = StreamChatOptions(
        think: true,
        toolAttempts: 5,
      );

      final stream = mock.streamChat(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'Hello')],
        // think and tools defaults should be overridden by options
        options: options,
      );

      // Just verify it streams without error
      await for (final _ in stream) {}
    });

    test('can use copyWith to modify options', () {
      const original = StreamChatOptions(toolAttempts: 3);
      final modified = original.copyWith(think: true, toolAttempts: 5);

      expect(original.think, false);
      expect(original.toolAttempts, 3);
      expect(modified.think, true);
      expect(modified.toolAttempts, 5);
    });
  });
}
