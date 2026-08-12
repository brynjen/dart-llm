import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

List<Map<String, dynamic>> _content(Map<String, dynamic> turn) =>
    (turn['content'] as List).cast<Map<String, dynamic>>();

void main() {
  group('GeminiMessageConverter.buildStatelessInput', () {
    test('emits role-tagged turns with typed content blocks', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.user, content: 'Hello Gemini'),
      ]);

      expect(input.length, 1);
      expect(input.first['role'], 'user');
      expect(_content(input.first), [
        {'type': 'text', 'text': 'Hello Gemini'},
      ]);
    });

    test('emits system messages as leading user turns', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
        LLMMessage(role: LLMRole.user, content: 'Hello'),
      ]);

      expect(input.length, 2);
      expect(input[0]['role'], 'user');
      expect(_content(input[0]).first['text'], 'You are helpful.');
      expect(_content(input[1]).first['text'], 'Hello');
      // There is no documented system role on the Interactions API.
      expect(input.every((turn) => turn['role'] != 'system'), isTrue);
    });

    test('keeps each system message as its own turn', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.system, content: 'First.'),
        LLMMessage(role: LLMRole.system, content: 'Second.'),
        LLMMessage(role: LLMRole.user, content: 'Hi'),
      ]);

      expect(input.length, 3);
      expect(_content(input[0]).first['text'], 'First.');
      expect(_content(input[1]).first['text'], 'Second.');
    });

    test('uses role "model" for assistant turns', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.user, content: 'Hi'),
        LLMMessage(role: LLMRole.assistant, content: 'Hello!'),
      ]);

      expect(input[1]['role'], 'model');
      expect(_content(input[1]).first, {'type': 'text', 'text': 'Hello!'});
    });

    test('converts assistant tool calls to function_call blocks', () {
      final input = GeminiMessageConverter.buildStatelessInput([
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
      ]);

      final block = _content(input[1]).first;
      expect(block['type'], 'function_call');
      expect(block['id'], 'call_1');
      expect(block['name'], 'calculator');
      expect(block['arguments'], {'expression': '2+2'});
    });

    test('converts tool results to function_result blocks', () {
      final input = GeminiMessageConverter.buildStatelessInput([
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
          content: 'Result: 4',
          toolCallId: 'c1',
          status: 'calculator',
        ),
      ]);

      expect(input[2]['role'], 'user');
      expect(_content(input[2]).first, {
        'type': 'function_result',
        'call_id': 'c1',
        'name': 'calculator',
        'result': [
          {'type': 'text', 'text': 'Result: 4'},
        ],
      });
    });

    test('merges consecutive tool results into a single turn', () {
      final input = GeminiMessageConverter.buildStatelessInput([
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
        LLMMessage(
          role: LLMRole.tool,
          content: '1',
          toolCallId: 'i1',
          status: 'tool1',
        ),
        LLMMessage(
          role: LLMRole.tool,
          content: '2',
          toolCallId: 'i2',
          status: 'tool2',
        ),
      ]);

      expect(input.length, 3); // user, model, merged tool results
      expect(_content(input[2]).length, 2);
      expect(_content(input[2])[1]['call_id'], 'i2');
    });

    test('converts images to image blocks with sniffed mime type', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(
          role: LLMRole.user,
          content: 'Describe',
          images: ['/9j/4AAQSkZJRgAB'],
        ),
      ]);

      final imageBlock = _content(input.first).first;
      expect(imageBlock['type'], 'image');
      expect(imageBlock['mime_type'], 'image/jpeg');
      expect(imageBlock['data'], '/9j/4AAQSkZJRgAB');
    });
  });

  group('GeminiMessageConverter.toolToFunctionSpec', () {
    test('produces a flat function entry', () {
      final spec = GeminiMessageConverter.toolToFunctionSpec(_TestTool());

      expect(spec['type'], 'function');
      expect(spec['name'], 'test_tool');
      expect(spec['description'], 'A test tool');
      expect(spec['parameters'], isA<Map>());
      // The Interactions API does not nest declarations.
      expect(spec.containsKey('functionDeclarations'), isFalse);
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
