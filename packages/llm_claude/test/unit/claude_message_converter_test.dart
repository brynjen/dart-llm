import 'dart:convert';

import 'package:llm_claude/llm_claude.dart';
import 'package:llm_claude/src/claude_message_converter.dart';
import 'package:test/test.dart';

void main() {
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
}
