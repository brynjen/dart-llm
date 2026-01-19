import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('Validation comprehensive', () {
    test('validates message content length', () {
      final longContent = 'a' * (Validation.maxMessageContentLength + 1);
      final message = LLMMessage(role: LLMRole.user, content: longContent);

      expect(
        () => Validation.validateMessage(message),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validates too many messages', () {
      final messages = List.generate(
        Validation.maxMessages + 1,
        (i) => LLMMessage(role: LLMRole.user, content: 'Message $i'),
      );

      expect(
        () => Validation.validateMessages(messages),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validates too many images', () {
      final images = List.generate(
        Validation.maxImagesPerMessage + 1,
        (i) => 'base64image$i',
      );
      final message = LLMMessage(
        role: LLMRole.user,
        content: 'Hello',
        images: images,
      );

      expect(
        () => Validation.validateMessage(message),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validates tool arguments', () {
      final validArgs = {'a': 1, 'b': 'test', 'c': true};
      expect(
        () => Validation.validateToolArguments(validArgs, 'test-tool'),
        returnsNormally,
      );

      // Too many arguments
      final manyArgs = <String, dynamic>{};
      for (int i = 0; i < 101; i++) {
        manyArgs['arg$i'] = i;
      }
      expect(
        () => Validation.validateToolArguments(manyArgs, 'test-tool'),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validates assistant message with content or tool calls', () {
      // Valid: has content
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.assistant, content: 'Response'),
        ),
        returnsNormally,
      );

      // Valid: has tool calls (even if content is empty)
      expect(
        () => Validation.validateMessage(
          LLMMessage(
            role: LLMRole.assistant,
            content: '', // Empty content is OK if toolCalls exist
            toolCalls: [{'name': 'tool', 'arguments': {}}],
          ),
        ),
        returnsNormally,
      );

      // Invalid: neither content nor tool calls
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.assistant),
        ),
        throwsA(isA<LLMApiException>()),
      );
    });
  });
}
