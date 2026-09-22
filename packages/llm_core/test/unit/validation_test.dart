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
      final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];
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
      final message = LLMMessage(role: LLMRole.tool, content: 'result');
      expect(
        () => Validation.validateMessage(message),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('validateMessage - tool message with toolCallId passes', () {
      final message = LLMMessage(
        role: LLMRole.tool,
        content: 'result',
        toolCallId: 'call_abc123',
      );
      expect(() => Validation.validateMessage(message), returnsNormally);
    });

    test('validateMessage - system message without content throws', () {
      final message = LLMMessage(role: LLMRole.system);
      expect(
        () => Validation.validateMessage(message),
        throwsA(isA<LLMApiException>()),
      );
    });
  });

  group('an empty user message is valid, a contentless one is not', () {
    // The distinction is easy to get wrong — an integration test asserted the
    // opposite for a long time and had never passed — so both halves are
    // pinned here.

    test('content: "" is accepted', () {
      // Every backend accepts an empty user message except Anthropic, and
      // ClaudeMessageConverter substitutes a non-whitespace placeholder for
      // it. Rejecting it here would make that placeholder unreachable and
      // fail a conversation on Claude that works everywhere else.
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.user, content: ''),
        ),
        returnsNormally,
      );
    });

    test('content: "" derives a content part, which is why it passes', () {
      final message = LLMMessage(role: LLMRole.user, content: '');

      expect(message.contentParts, hasLength(1));
      expect(message.contentParts.single, const LLMTextContent(''));
    });

    test('a message carrying nothing at all is rejected', () {
      expect(
        () => Validation.validateMessage(LLMMessage(role: LLMRole.user)),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('images alone are enough', () {
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.user, images: ['base64']),
        ),
        returnsNormally,
      );
    });

    test('content parts alone are enough', () {
      expect(
        () => Validation.validateMessage(
          LLMMessage(
            role: LLMRole.user,
            contentParts: const [LLMTextContent('hi')],
          ),
        ),
        returnsNormally,
      );
    });

    test('explicit empty parts alongside real content are accepted', () {
      // Why the guard cannot be reduced to `contentParts.isEmpty`: this
      // message carries text even though its parts list is empty.
      expect(
        () => Validation.validateMessage(
          LLMMessage(role: LLMRole.user, content: 'hi', contentParts: const []),
        ),
        returnsNormally,
      );
    });

    test('the whole-list validator agrees', () {
      expect(
        () => Validation.validateMessages([
          LLMMessage(role: LLMRole.user, content: ''),
        ]),
        returnsNormally,
      );
      expect(
        () => Validation.validateMessages([LLMMessage(role: LLMRole.user)]),
        throwsA(isA<LLMApiException>()),
      );
    });
  });
}
