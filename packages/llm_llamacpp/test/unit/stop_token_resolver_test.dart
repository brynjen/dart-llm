import 'package:llm_llamacpp/src/stop_token_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('resolveStopTokens', () {
    const chatMlPrompt =
        '<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n';
    const llama3Prompt =
        '<|start_header_id|>user<|end_header_id|>\nHello<|eot_id|>';

    test('detects the ChatML turn-end marker from the rendered template', () {
      expect(
        resolveStopTokens(requested: const [], prompt: chatMlPrompt),
        ['<|im_end|>'],
      );
    });

    test('detects the Llama-3 turn-end marker', () {
      expect(
        resolveStopTokens(requested: const [], prompt: llama3Prompt),
        ['<|eot_id|>'],
      );
    });

    test('adds nothing for a template with no recognised marker', () {
      expect(
        resolveStopTokens(
          requested: const [],
          prompt: '<start_of_turn>user\nHello<end_of_turn>\n',
        ),
        isEmpty,
      );
    });

    test('appends detected markers to caller-supplied stops, keeping both', () {
      // The regression this guards: a caller configuring Gemma's marker must not
      // lose the auto-detected ChatML marker, and vice versa.
      expect(
        resolveStopTokens(
          requested: const ['<end_of_turn>'],
          prompt: chatMlPrompt,
        ),
        ['<end_of_turn>', '<|im_end|>'],
      );
    });

    test('preserves caller order and every caller-supplied stop', () {
      expect(
        resolveStopTokens(
          requested: const ['<|end|>', '<end_of_turn>'],
          prompt: llama3Prompt,
        ),
        ['<|end|>', '<end_of_turn>', '<|eot_id|>'],
      );
    });

    test('does not duplicate a stop the caller already named', () {
      expect(
        resolveStopTokens(
          requested: const ['<|im_end|>'],
          prompt: chatMlPrompt,
        ),
        ['<|im_end|>'],
      );
    });

    test('keeps caller stops when the template is unrecognised', () {
      expect(
        resolveStopTokens(
          requested: const ['<|end|>'],
          prompt: 'plain prompt with no markers',
        ),
        ['<|end|>'],
      );
    });

    test('reports each detected marker exactly once via onDiagnostic', () {
      final messages = <String>[];
      resolveStopTokens(
        requested: const ['<|im_end|>'],
        prompt: '$chatMlPrompt$llama3Prompt',
        onDiagnostic: messages.add,
      );

      // `<|im_end|>` was supplied by the caller, so only the Llama-3 marker is
      // newly detected and only it should be reported.
      expect(messages, hasLength(1));
      expect(messages.single, contains('<|eot_id|>'));
    });

    test('does not mutate the caller-supplied list', () {
      final requested = <String>['<end_of_turn>'];
      resolveStopTokens(requested: requested, prompt: chatMlPrompt);
      expect(requested, ['<end_of_turn>']);
    });

    test('accepts a const empty list as the default', () {
      // `LlamaCppChatRepository.stopTokens` defaults to `const []`, which would
      // throw if the resolver appended to it in place.
      expect(
        () => resolveStopTokens(requested: const [], prompt: chatMlPrompt),
        returnsNormally,
      );
    });
  });
}
