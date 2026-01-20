import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('LLMMessage.toJson', () {
    test('user message with content only', () {
      final message = LLMMessage(role: LLMRole.user, content: 'Hello, world!');

      final json = message.toJson();

      expect(json['role'], 'user');
      expect(json['content'], isA<List>());
      final content = json['content'] as List;
      expect(content.length, 1);
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], 'Hello, world!');
    });

    test('user message with images only', () {
      final message = LLMMessage(
        role: LLMRole.user,
        images: ['base64image1', 'base64image2'],
      );

      final json = message.toJson();

      expect(json['role'], 'user');
      expect(json['content'], isA<List>());
      final content = json['content'] as List;
      expect(content.length, 2);
      expect(content[0]['type'], 'image_url');
      expect(
        content[0]['image_url']['url'],
        'data:image/png;base64,base64image1',
      );
      expect(content[1]['type'], 'image_url');
      expect(
        content[1]['image_url']['url'],
        'data:image/png;base64,base64image2',
      );
    });

    test('user message with content and images', () {
      final message = LLMMessage(
        role: LLMRole.user,
        content: 'What is in this image?',
        images: ['base64image1'],
      );

      final json = message.toJson();

      expect(json['role'], 'user');
      expect(json['content'], isA<List>());
      final content = json['content'] as List;
      expect(content.length, 2);
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], 'What is in this image?');
      expect(content[1]['type'], 'image_url');
      expect(
        content[1]['image_url']['url'],
        'data:image/png;base64,base64image1',
      );
    });

    test('system message with content', () {
      final message = LLMMessage(
        role: LLMRole.system,
        content: 'You are a helpful assistant.',
      );

      final json = message.toJson();

      expect(json['role'], 'system');
      expect(json['content'], 'You are a helpful assistant.');
    });

    test('assistant message with content', () {
      final message = LLMMessage(
        role: LLMRole.assistant,
        content: 'Hello! How can I help you?',
      );

      final json = message.toJson();

      expect(json['role'], 'assistant');
      expect(json['content'], 'Hello! How can I help you?');
    });

    test('assistant message with tool calls', () {
      final message = LLMMessage(
        role: LLMRole.assistant,
        content: 'I will calculate that.',
        toolCalls: [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'calculator', 'arguments': '{"a": 2, "b": 2}'},
          },
        ],
      );

      final json = message.toJson();

      expect(json['role'], 'assistant');
      expect(json['content'], 'I will calculate that.');
      expect(json['tool_calls'], isA<List>());
      expect(json['tool_calls'].length, 1);
    });

    test('tool message with tool call ID and content', () {
      final message = LLMMessage(
        role: LLMRole.tool,
        content: '4',
        toolCallId: 'call_1',
      );

      final json = message.toJson();

      expect(json['role'], 'tool');
      expect(json['content'], '4');
      expect(json['tool_call_id'], 'call_1');
    });

    test('user message with empty images list', () {
      final message = LLMMessage(
        role: LLMRole.user,
        content: 'Hello',
        images: [],
      );

      final json = message.toJson();

      expect(json['role'], 'user');
      expect(json['content'], isA<List>());
      final content = json['content'] as List;
      expect(content.length, 1);
      expect(content[0]['type'], 'text');
    });

    test('user message with null content and null images', () {
      final message = LLMMessage(role: LLMRole.user);

      final json = message.toJson();

      expect(json['role'], 'user');
      expect(json['content'], isA<List>());
      expect((json['content'] as List).isEmpty, true);
    });

    test('assistant message with null content', () {
      final message = LLMMessage(role: LLMRole.assistant);

      final json = message.toJson();

      expect(json['role'], 'assistant');
      expect(json['content'], null);
    });

    test('message with status field', () {
      final message = LLMMessage(
        role: LLMRole.user,
        content: 'Hello',
        status: 'processing',
      );

      final json = message.toJson();

      expect(json['role'], 'user');
      // Status is not included in toJson (it's application-level)
      expect(json.containsKey('status'), false);
    });
  });
}
