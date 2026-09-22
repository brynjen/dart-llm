import 'package:llm_core/llm_core.dart';
import 'package:llm_ollama/src/message_converter.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaMessageConverter', () {
    test(
      'messagesToOllamaJson derives tool_name from preceding assistant tool_calls',
      () {
        final messages = [
          LLMMessage(role: LLMRole.user, content: 'What is 2+2?'),
          LLMMessage(
            role: LLMRole.assistant,
            toolCalls: [
              {
                'id': 'call_abc123',
                'type': 'function',
                'function': {
                  'name': 'calculator',
                  'arguments': '{"expr":"2+2"}',
                },
              },
            ],
          ),
          LLMMessage(
            role: LLMRole.tool,
            content: '4',
            toolCallId: 'call_abc123',
          ),
        ];

        final result = OllamaMessageConverter.messagesToOllamaJson(messages);

        expect(result.length, 3);
        final toolJson = result[2];
        expect(toolJson['role'], 'tool');
        expect(toolJson['content'], '4');
        expect(toolJson['tool_call_id'], 'call_abc123');
        expect(toolJson['tool_name'], 'calculator');
      },
    );

    test(
      'messagesToOllamaJson derives tool_name from synthetic ID when no match',
      () {
        final messages = [
          LLMMessage(role: LLMRole.user, content: 'Echo'),
          LLMMessage(
            role: LLMRole.tool,
            content: '{"a":1}',
            toolCallId: 'tool_0_echo_tool',
          ),
        ];

        final result = OllamaMessageConverter.messagesToOllamaJson(messages);

        expect(result.length, 2);
        final toolJson = result[1];
        expect(toolJson['role'], 'tool');
        expect(toolJson['tool_call_id'], 'tool_0_echo_tool');
        expect(toolJson['tool_name'], 'echo_tool');
      },
    );

    test(
      'messagesToOllamaJson sends tool_call_id only when tool_name cannot be derived',
      () {
        final messages = [
          LLMMessage(
            role: LLMRole.tool,
            content: 'result',
            toolCallId: 'openai_style_call_xyz',
          ),
        ];

        final result = OllamaMessageConverter.messagesToOllamaJson(messages);

        expect(result.length, 1);
        final toolJson = result[0];
        expect(toolJson['role'], 'tool');
        expect(toolJson['tool_call_id'], 'openai_style_call_xyz');
        expect(toolJson.containsKey('tool_name'), isFalse);
      },
    );
  });

  group('tool_name from the executor', () {
    List<Map<String, dynamic>> convert(LLMMessage toolMessage) =>
        OllamaMessageConverter.messagesToOllamaJson([
          LLMMessage(role: LLMRole.user, content: 'What is 2+2?'),
          LLMMessage(
            role: LLMRole.assistant,
            toolCalls: [
              {
                'id': 'call_abc123',
                'type': 'function',
                'function': {'name': 'calculator', 'arguments': '{}'},
              },
            ],
          ),
          toolMessage,
        ]);

    test('toolName is used directly, no derivation needed', () {
      final result = convert(
        LLMMessage(
          role: LLMRole.tool,
          content: '4',
          // An id that the backwards walk could never match, proving the name
          // came from the field rather than from re-deriving it.
          toolCallId: 'unmatchable_id',
          toolName: 'calculator',
        ),
      );

      expect(result.last['tool_name'], 'calculator');
    });

    test('the derivation still covers a caller-built history', () {
      final result = convert(
        LLMMessage(role: LLMRole.tool, content: '4', toolCallId: 'call_abc123'),
      );

      expect(result.last['tool_name'], 'calculator');
    });

    test('reasoning never reaches the Ollama payload', () {
      final result = OllamaMessageConverter.messagesToOllamaJson([
        LLMMessage(
          role: LLMRole.assistant,
          content: 'Hello',
          thinking: 'the user greeted me',
        ),
      ]);

      expect(result.single.containsKey('thinking'), isFalse);
      expect(result.single.toString(), isNot(contains('greeted me')));
    });
  });
}
