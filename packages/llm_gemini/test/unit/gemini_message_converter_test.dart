import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

List<Map<String, dynamic>> _content(Map<String, dynamic> step) =>
    (step['content'] as List).cast<Map<String, dynamic>>();

void main() {
  group('GeminiMessageConverter.buildStatelessInput (steps format)', () {
    test('emits user messages as user_input steps with typed content', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.user, content: 'Hello Gemini'),
      ]);

      expect(input.length, 1);
      expect(input.first['type'], 'user_input');
      expect(_content(input.first), [
        {'type': 'text', 'text': 'Hello Gemini'},
      ]);
    });

    test('emits system messages as leading user_input steps', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
        LLMMessage(role: LLMRole.user, content: 'Hello'),
      ]);

      expect(input.length, 2);
      expect(input[0]['type'], 'user_input');
      expect(_content(input[0]).first['text'], 'You are helpful.');
      expect(_content(input[1]).first['text'], 'Hello');
    });

    test('keeps each system message as its own step', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.system, content: 'First.'),
        LLMMessage(role: LLMRole.system, content: 'Second.'),
        LLMMessage(role: LLMRole.user, content: 'Hi'),
      ]);

      expect(input.length, 3);
      expect(_content(input[0]).first['text'], 'First.');
      expect(_content(input[1]).first['text'], 'Second.');
    });

    test('emits assistant text as model_output steps', () {
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.user, content: 'Hi'),
        LLMMessage(role: LLMRole.assistant, content: 'Hello!'),
      ]);

      expect(input[1]['type'], 'model_output');
      expect(_content(input[1]).first, {'type': 'text', 'text': 'Hello!'});
    });

    test('converts assistant tool calls to top-level function_call steps', () {
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

      final step = input[1];
      expect(step['type'], 'function_call');
      expect(step['id'], 'call_1');
      expect(step['name'], 'calculator');
      expect(step['arguments'], {'expression': '2+2'});
    });

    test('echoes a smuggled thought signature before the function_call', () {
      const sep = GeminiMessageConverter.signatureSeparator;
      final input = GeminiMessageConverter.buildStatelessInput([
        LLMMessage(role: LLMRole.user, content: 'Calculate'),
        LLMMessage(
          role: LLMRole.assistant,
          toolCalls: [
            {
              'id': 'call_1${sep}SIG_A',
              'function': {'name': 'calculator', 'arguments': '{}'},
            },
          ],
        ),
        LLMMessage(
          role: LLMRole.tool,
          content: '4',
          toolCallId: 'call_1${sep}SIG_A',
          status: 'calculator',
        ),
      ]);

      expect(input[1], {'type': 'thought', 'signature': 'SIG_A'});
      expect(input[2]['type'], 'function_call');
      expect(input[2]['id'], 'call_1'); // signature stripped
      expect(input[3]['type'], 'function_result');
      expect(input[3]['call_id'], 'call_1'); // signature stripped
    });

    test(
      'one thought step covers consecutive calls with the same signature',
      () {
        const sep = GeminiMessageConverter.signatureSeparator;
        final input = GeminiMessageConverter.buildStatelessInput([
          LLMMessage(role: LLMRole.user, content: 'Run tools'),
          LLMMessage(
            role: LLMRole.assistant,
            toolCalls: [
              {
                'id': 'i1${sep}SIG',
                'function': {'name': 'tool1', 'arguments': '{}'},
              },
              {
                'id': 'i2${sep}SIG',
                'function': {'name': 'tool2', 'arguments': '{}'},
              },
            ],
          ),
        ]);

        final types = input.map((s) => s['type']).toList();
        expect(types, [
          'user_input',
          'thought',
          'function_call',
          'function_call',
        ]);
      },
    );

    test('converts tool results to function_result steps', () {
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

      expect(input[2], {
        'type': 'function_result',
        'call_id': 'c1',
        'name': 'calculator',
        'result': [
          {'type': 'text', 'text': 'Result: 4'},
        ],
      });
    });

    test('parallel tool results are separate consecutive steps', () {
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

      // user_input, function_call x2, function_result x2
      expect(input.length, 5);
      expect(input[3]['type'], 'function_result');
      expect(input[4]['type'], 'function_result');
      expect(input[4]['call_id'], 'i2');
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
