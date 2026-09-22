import 'dart:convert';

import 'package:llm_claude/llm_claude.dart';
import 'package:llm_claude/src/claude_message_converter.dart';
import 'package:test/test.dart';

void main() {
  _emptyContentTests();

  group('ClaudeMessageConverter', () {
    test('extracts system message into system field', () {
      final messages = [
        LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
        LLMMessage(role: LLMRole.user, content: 'Hello'),
      ];
      final result = ClaudeMessageConverter.convert(messages);
      expect(result.system, 'You are helpful.');
      expect(result.messages.length, 1);
      expect(result.messages[0]['role'], 'user');
    });

    test('concatenates multiple system messages', () {
      final messages = [
        LLMMessage(role: LLMRole.system, content: 'First.'),
        LLMMessage(role: LLMRole.system, content: 'Second.'),
        LLMMessage(role: LLMRole.user, content: 'Hi'),
      ];
      final result = ClaudeMessageConverter.convert(messages);
      expect(result.system, 'First.\n\nSecond.');
    });

    test('converts user message to content blocks', () {
      final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];
      final result = ClaudeMessageConverter.convert(messages);
      expect(result.system, isNull);
      final msg = result.messages[0];
      expect(msg['role'], 'user');
      final content = msg['content'] as List;
      expect(content.length, 1);
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], 'Hello');
    });

    test('converts assistant message with text', () {
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Hello'),
        LLMMessage(role: LLMRole.assistant, content: 'Hi there!'),
      ];
      final result = ClaudeMessageConverter.convert(messages);
      final assistantMsg = result.messages[1];
      expect(assistantMsg['role'], 'assistant');
      final content = assistantMsg['content'] as List;
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], 'Hi there!');
    });

    test('converts assistant message with tool calls', () {
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Calculate 2+2'),
        LLMMessage(
          role: LLMRole.assistant,
          content: null,
          toolCalls: [
            {
              'id': 'toolu_01',
              'function': {
                'name': 'calculator',
                'arguments': '{"expression": "2+2"}',
              },
            },
          ],
        ),
      ];
      final result = ClaudeMessageConverter.convert(messages);
      final assistantMsg = result.messages[1];
      expect(assistantMsg['role'], 'assistant');
      final content = assistantMsg['content'] as List;
      final toolUse = content.firstWhere((b) => b['type'] == 'tool_use');
      expect(toolUse['type'], 'tool_use');
      expect(toolUse['id'], 'toolu_01');
      expect(toolUse['name'], 'calculator');
      expect((toolUse['input'] as Map)['expression'], '2+2');
    });

    test(
      'converts tool result message to user message with tool_result block',
      () {
        final messages = [
          LLMMessage(role: LLMRole.user, content: 'Calculate'),
          LLMMessage(
            role: LLMRole.assistant,
            toolCalls: [
              {
                'id': 'toolu_01',
                'function': {'name': 'calculator', 'arguments': '{}'},
              },
            ],
          ),
          LLMMessage(
            role: LLMRole.tool,
            content: 'Result: 4',
            toolCallId: 'toolu_01',
          ),
        ];
        final result = ClaudeMessageConverter.convert(messages);
        final toolMsg = result.messages[2];
        expect(toolMsg['role'], 'user');
        final content = toolMsg['content'] as List;
        expect(content[0]['type'], 'tool_result');
        expect(content[0]['tool_use_id'], 'toolu_01');
        expect(content[0]['content'], 'Result: 4');
      },
    );

    test('merges consecutive tool results into single user message', () {
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Use tools'),
        LLMMessage(
          role: LLMRole.assistant,
          toolCalls: [
            {
              'id': 'id1',
              'function': {'name': 'tool1', 'arguments': '{}'},
            },
            {
              'id': 'id2',
              'function': {'name': 'tool2', 'arguments': '{}'},
            },
          ],
        ),
        LLMMessage(role: LLMRole.tool, content: 'Result 1', toolCallId: 'id1'),
        LLMMessage(role: LLMRole.tool, content: 'Result 2', toolCallId: 'id2'),
      ];
      final result = ClaudeMessageConverter.convert(messages);
      // Tool results should be merged into one user message
      expect(result.messages.length, 3); // user, assistant, merged-user
      final toolMsg = result.messages[2];
      expect(toolMsg['role'], 'user');
      final content = toolMsg['content'] as List;
      expect(content.length, 2);
      expect(content[0]['tool_use_id'], 'id1');
      expect(content[1]['tool_use_id'], 'id2');
    });

    test('detects JPEG image from base64 prefix', () {
      // JPEG magic bytes in base64 start with /9j/
      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'What is this?',
          images: ['/9j/4AAQSkZJRgAB'],
        ),
      ];
      final result = ClaudeMessageConverter.convert(messages);
      final content = result.messages[0]['content'] as List;
      final imageBlock = content.firstWhere((b) => b['type'] == 'image');
      expect(imageBlock['source']['media_type'], 'image/jpeg');
    });

    test('detects PNG image from base64 prefix', () {
      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Describe',
          images: ['iVBORw0KGgoAAAANSUhEUgAA'],
        ),
      ];
      final result = ClaudeMessageConverter.convert(messages);
      final content = result.messages[0]['content'] as List;
      final imageBlock = content.firstWhere((b) => b['type'] == 'image');
      expect(imageBlock['source']['media_type'], 'image/png');
    });

    test('parses data URI for media type', () {
      final fakeBase64 = base64.encode([1, 2, 3]);
      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Image',
          images: ['data:image/webp;base64,$fakeBase64'],
        ),
      ];
      final result = ClaudeMessageConverter.convert(messages);
      final content = result.messages[0]['content'] as List;
      final imageBlock = content.firstWhere((b) => b['type'] == 'image');
      expect(imageBlock['source']['media_type'], 'image/webp');
      expect(imageBlock['source']['data'], fakeBase64);
    });
  });

  group('tool_result is_error', () {
    Map<String, dynamic> resultBlock(LLMMessage toolMessage) {
      final result = ClaudeMessageConverter.convert([
        LLMMessage(role: LLMRole.user, content: 'Use a tool'),
        LLMMessage(
          role: LLMRole.assistant,
          toolCalls: [
            {
              'id': 'id1',
              'function': {'name': 'calculator', 'arguments': '{}'},
            },
          ],
        ),
        toolMessage,
      ]);
      final content = result.messages.last['content'] as List;
      return content.first as Map<String, dynamic>;
    }

    test('comes from toolResult.isError when present', () {
      final block = resultBlock(
        LLMMessage(
          role: LLMRole.tool,
          content: 'anything at all',
          toolCallId: 'id1',
          toolName: 'calculator',
          toolResult: const LLMToolResult.failure('anything at all'),
        ),
      );

      expect(block['is_error'], isTrue);
    });

    test('a successful result is not flagged, whatever its text says', () {
      // The old text match flagged any output starting 'Tool x failed:', even
      // when the tool had succeeded and was merely reporting about one.
      final block = resultBlock(
        LLMMessage(
          role: LLMRole.tool,
          content: 'Tool calculator failed: is what the log said',
          toolCallId: 'id1',
          toolName: 'calculator',
          toolResult: const LLMToolResult(
            content: 'Tool calculator failed: is what the log said',
          ),
        ),
      );

      expect(block.containsKey('is_error'), isFalse);
    });

    test('an invalid call now reaches Anthropic flagged', () {
      // Regression: StreamToolExecutor words this 'was not called', which the
      // 'Tool <name> failed:' match missed, so a parse error was sent as a
      // successful result and the model read the error message as data.
      final block = resultBlock(
        LLMMessage(
          role: LLMRole.tool,
          content:
              'Tool calculator was not called: its arguments are not valid '
              'JSON (Unexpected end of input).',
          toolCallId: 'id1',
          toolName: 'calculator',
          toolResult: const LLMToolResult.failure(
            'Tool calculator was not called: its arguments are not valid JSON.',
          ),
        ),
      );

      expect(block['is_error'], isTrue);
    });

    test('falls back to the text match for a caller-built history', () {
      final block = resultBlock(
        LLMMessage(
          role: LLMRole.tool,
          content: 'Tool calculator failed: boom',
          toolCallId: 'id1',
          toolName: 'calculator',
        ),
      );

      expect(block['is_error'], isTrue);
    });

    test('still reads status for a history serialized before toolName', () {
      final block = resultBlock(
        LLMMessage(
          role: LLMRole.tool,
          content: 'Tool calculator failed: boom',
          toolCallId: 'id1',
          status: 'calculator',
        ),
      );

      expect(block['is_error'], isTrue);
    });

    test('content parts become Anthropic blocks', () {
      // Anthropic accepts text/image/document/search_result blocks inside a
      // tool_result, so a tool returning a screenshot sends the image itself.
      final block = resultBlock(
        LLMMessage(
          role: LLMRole.tool,
          content: 'a screenshot of the page',
          toolCallId: 'id1',
          toolName: 'screenshot',
          toolResult: const LLMToolResult(
            content: 'a screenshot of the page',
            contentParts: [
              LLMTextContent('a screenshot of the page'),
              LLMImageContent('iVBORw0KGgo='),
            ],
          ),
        ),
      );

      final content = block['content'] as List;
      expect(content, hasLength(2));
      expect(content[0], {'type': 'text', 'text': 'a screenshot of the page'});
      expect(content[1]['type'], 'image');
      expect(content[1]['source']['media_type'], 'image/png');
    });

    test('a text-only result still sends a plain string', () {
      final block = resultBlock(
        LLMMessage(
          role: LLMRole.tool,
          content: '4',
          toolCallId: 'id1',
          toolName: 'calculator',
          toolResult: const LLMToolResult(content: '4'),
        ),
      );

      expect(block['content'], '4');
    });

    test('an assistant turn never leaks its reasoning', () {
      final result = ClaudeMessageConverter.convert([
        LLMMessage(role: LLMRole.user, content: 'Hi'),
        LLMMessage(
          role: LLMRole.assistant,
          content: 'Hello',
          thinking: 'the user greeted me',
        ),
      ]);

      expect(jsonEncode(result.messages), isNot(contains('greeted me')));
    });
  });
}

void _emptyContentTests() {
  /// Every text block the converter produced, flattened.
  List<String> textsOf(Map<String, dynamic> message) =>
      (message['content'] as List)
          .cast<Map<String, dynamic>>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'] as String)
          .toList();

  group('ClaudeMessageConverter empty content', () {
    test('an empty message becomes a non-whitespace placeholder', () {
      // Anthropic has no valid representation of an empty message: `''`, `[]`,
      // an empty text block and a whitespace-only text block are all rejected
      // ("text content blocks must contain non-whitespace text"), and so is an
      // empty `messages` array. The converter has always substituted a
      // placeholder; it just used a single space, which the API rejects for
      // exactly that reason.
      for (final role in [LLMRole.user, LLMRole.assistant]) {
        final result = ClaudeMessageConverter.convert([
          if (role == LLMRole.assistant)
            LLMMessage(role: LLMRole.user, content: 'hi'),
          LLMMessage(role: role, content: ''),
        ]);
        final texts = textsOf(result.messages.last);
        expect(texts, isNotEmpty, reason: '$role must produce a text block');
        for (final text in texts) {
          expect(text, isNotEmpty, reason: '$role: minLength is 1');
          expect(
            text.trim(),
            isNotEmpty,
            reason: '$role: an all-whitespace block is rejected too',
          );
        }
      }
    });

    test('real content is never replaced', () {
      final result = ClaudeMessageConverter.convert([
        LLMMessage(role: LLMRole.user, content: 'Hello'),
      ]);
      expect(textsOf(result.messages.single), ['Hello']);
    });

    test('an assistant turn carrying only tool calls needs no placeholder', () {
      final result = ClaudeMessageConverter.convert([
        LLMMessage(role: LLMRole.user, content: 'weather?'),
        LLMMessage(
          role: LLMRole.assistant,
          content: null,
          toolCalls: [
            {
              'id': 'toolu_1',
              'type': 'function',
              'function': {
                'name': 'get_weather',
                'arguments': '{"city":"Oslo"}',
              },
            },
          ],
        ),
      ]);
      final blocks = (result.messages.last['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(blocks.single['type'], 'tool_use');
    });
  });
}
