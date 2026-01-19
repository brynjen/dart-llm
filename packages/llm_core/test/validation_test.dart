import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('Validation', () {
    test('validateModelName - empty model name throws', () {
      expect(
        () => Validation.validateModelName(''),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validateModelName - valid model name passes', () {
      expect(() => Validation.validateModelName('gpt-4o'), returnsNormally);
    });

    test('validateModelName - too long model name throws', () {
      final longName = 'a' * 201;
      expect(
        () => Validation.validateModelName(longName),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validateMessages - empty list throws', () {
      expect(
        () => Validation.validateMessages([]),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validateMessages - valid messages pass', () {
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Hello'),
      ];
      expect(() => Validation.validateMessages(messages), returnsNormally);
    });

    test('validateMessage - user message without content or images throws', () {
      final message = LLMMessage(role: LLMRole.user);
      expect(
        () => Validation.validateMessage(message),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validateMessage - tool message without toolCallId throws', () {
      final message = LLMMessage(
        role: LLMRole.tool,
        content: 'result',
      );
      expect(
        () => Validation.validateMessage(message),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validateMessage - system message without content throws', () {
      final message = LLMMessage(role: LLMRole.system);
      expect(
        () => Validation.validateMessage(message),
        throwsA(isA<LLMApiException>()),
      );
    });
  });
}
