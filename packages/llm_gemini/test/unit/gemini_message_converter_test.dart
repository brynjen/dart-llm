import 'package:llm_gemini/llm_gemini.dart';
import 'package:llm_gemini/src/gemini_message_converter.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiMessageConverter', () {
    test('extracts system message into systemInstruction', () {
      final messages = [
        LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
        LLMMessage(role: LLMRole.user, content: 'Hello'),
      ];
      final result = GeminiMessageConverter.convert(messages);
      expect(result.systemInstruction, isNotNull);
      final parts = result.systemInstruction!['parts'] as List;
      expect(parts.first['text'], 'You are helpful.');
      expect(result.contents.length, 1);
    });

    test('concatenates multiple system messages', () {
      final messages = [
        LLMMessage(role: LLMRole.system, content: 'First.'),
        LLMMessage(role: LLMRole.system, content: 'Second.'),
        LLMMessage(role: LLMRole.user, content: 'Hi'),
      ];
      final result = GeminiMessageConverter.convert(messages);
      final parts = result.systemInstruction!['parts'] as List;
      expect(parts.first['text'], 'First.\n\nSecond.');
    });

    test('converts user message with role "user"', () {
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Hello Gemini'),
      ];
      final result = GeminiMessageConverter.convert(messages);
      expect(result.contents.length, 1);
      final content = result.contents[0];
      expect(content['role'], 'user');
      final parts = content['parts'] as List;
      expect(parts.first['text'], 'Hello Gemini');
    });

    test('converts assistant message with role "model"', () {
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Hi'),
        LLMMessage(role: LLMRole.assistant, content: 'Hello!'),
      ];
      final result = GeminiMessageConverter.convert(messages);
      final modelContent = result.contents[1];
      expect(modelContent['role'], 'model');
      final parts = modelContent['parts'] as List;
      expect(parts.first['text'], 'Hello!');
    });

    test(
      'converts assistant message with tool calls to functionCall parts',
      () {
        final messages = [
          LLMMessage(role: LLMRole.user, content: 'Calculate'),
          LLMMessage(
            role: LLMRole.assistant,
            toolCalls: [
              {
                'id': 'call_1',
                'function': {
                  'name': 'calculator',
                  'arguments': '{"expression": "2+2"}',
                },
              },
            ],
          ),
        ];
        final result = GeminiMessageConverter.convert(messages);
        final modelContent = result.contents[1];
        expect(modelContent['role'], 'model');
        final parts = modelContent['parts'] as List;
        final fcPart =
            parts.firstWhere((p) => (p as Map).containsKey('functionCall'))
                as Map;
        expect(fcPart['functionCall']['name'], 'calculator');
        expect(fcPart['functionCall']['args']['expression'], '2+2');
      },
    );

    test('converts tool result to user message with functionResponse part', () {
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Calculate'),
        LLMMessage(
          role: LLMRole.assistant,
          toolCalls: [
            {
              'id': 'c1',
              'function': {'name': 'calculator', 'arguments': '{}'},
            },
          ],
        ),
        LLMMessage(
          role: LLMRole.tool,
          content: '{"result": 4}',
          toolCallId: 'c1',
        ),
      ];
      final result = GeminiMessageConverter.convert(messages);
      final toolContent = result.contents[2];
      expect(toolContent['role'], 'user');
      final parts = toolContent['parts'] as List;
      final frPart = parts.first as Map;
      expect(frPart['functionResponse'], isNotNull);
      expect(frPart['functionResponse']['response']['result'], 4);
    });

    test('merges consecutive tool results into one user content', () {
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Run tools'),
        LLMMessage(
          role: LLMRole.assistant,
          toolCalls: [
            {
              'id': 'i1',
              'function': {'name': 'tool1', 'arguments': '{}'},
            },
            {
              'id': 'i2',
              'function': {'name': 'tool2', 'arguments': '{}'},
            },
          ],
        ),
        LLMMessage(role: LLMRole.tool, content: '{"r": 1}', toolCallId: 'i1'),
        LLMMessage(role: LLMRole.tool, content: '{"r": 2}', toolCallId: 'i2'),
      ];
      final result = GeminiMessageConverter.convert(messages);
      expect(result.contents.length, 3); // user, model, merged-user
      final toolContent = result.contents[2];
      final parts = toolContent['parts'] as List;
      expect(parts.length, 2);
    });

    test('converts image to inlineData part', () {
      final messages = [
        LLMMessage(
          role: LLMRole.user,
          content: 'Describe',
          images: ['/9j/4AAQSkZJRgAB'],
        ),
      ];
      final result = GeminiMessageConverter.convert(messages);
      final parts = result.contents[0]['parts'] as List;
      final imagePart =
          parts.firstWhere((p) => (p as Map).containsKey('inlineData')) as Map;
      expect(imagePart['inlineData']['mimeType'], 'image/jpeg');
    });

    test('toolToFunctionDeclaration converts tool format', () {
      // Test with a minimal LLMTool-like object. Since LLMTool is abstract
      // we use LLMTool.toJson format through the converter's static method.
      // We'll verify the output structure.
      final declaration = GeminiMessageConverter.toolToFunctionDeclaration(
        _TestTool(),
      );
      expect(declaration['name'], 'test_tool');
      expect(declaration['description'], 'A test tool');
      expect(declaration['parameters'], isA<Map>());
    });
  });
}

class _TestTool extends LLMTool {
  @override
  String get name => 'test_tool';

  @override
  String get description => 'A test tool';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'input',
      type: 'string',
      description: 'Input value',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return 'result: ${args['input']}';
  }
}
