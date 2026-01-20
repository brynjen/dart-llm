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
            toolCalls: [
              {'name': 'tool', 'arguments': {}},
            ],
          ),
        ),
        returnsNormally,
      );

      // Invalid: neither content nor tool calls
      expect(
        () => Validation.validateMessage(LLMMessage(role: LLMRole.assistant)),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('model name validation edge cases', () {
      // Whitespace-only
      expect(
        () => Validation.validateModelName('   '),
        throwsA(isA<LLMApiException>()),
      );

      // Special characters (should be allowed in model names)
      expect(
        () => Validation.validateModelName('gpt-4o'),
        returnsNormally,
      );
      expect(
        () => Validation.validateModelName('model_name'),
        returnsNormally,
      );
      expect(
        () => Validation.validateModelName('model.name'),
        returnsNormally,
      );

      // Unicode characters
      expect(
        () => Validation.validateModelName('模型名称'),
        returnsNormally,
      );
    });

    test('message validation with all role combinations', () {
      // System message must have content
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.system, content: 'System prompt'),
        ),
        returnsNormally,
      );
      expect(
        () => Validation.validateMessage(LLMMessage(role: LLMRole.system)),
        throwsA(isA<LLMApiException>()),
      );

      // User message must have content or images
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.user, content: 'Hello'),
        ),
        returnsNormally,
      );
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.user, images: ['base64']),
        ),
        returnsNormally,
      );
      expect(
        () => Validation.validateMessage(LLMMessage(role: LLMRole.user)),
        throwsA(isA<LLMApiException>()),
      );

      // Tool message must have toolCallId
      expect(
        () => Validation.validateMessage(
          LLMMessage(
            role: LLMRole.tool,
            content: 'Result',
            toolCallId: 'call_1',
          ),
        ),
        returnsNormally,
      );
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.tool, content: 'Result'),
        ),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('tool argument validation edge cases', () {
      // Missing required field (validation doesn't check this, but we test structure)
      final args = {'optional': 'value'};
      expect(
        () => Validation.validateToolArguments(args, 'test-tool'),
        returnsNormally,
      );

      // Wrong types (validation doesn't check types, but we test structure)
      final wrongTypes = {
        'string': 123, // Should be string
        'number': 'not a number', // Should be number
      };
      expect(
        () => Validation.validateToolArguments(wrongTypes, 'test-tool'),
        returnsNormally, // Type validation is not done here
      );

      // Extra fields (validation doesn't check this)
      final extraFields = {
        'required': 'value',
        'extra': 'field',
      };
      expect(
        () => Validation.validateToolArguments(extraFields, 'test-tool'),
        returnsNormally,
      );
    });
  });
}
