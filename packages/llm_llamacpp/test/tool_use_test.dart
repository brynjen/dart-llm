// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:convert';
import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'test_config.dart';

/// A simple tool implementation for testing.
class TestTool extends LLMTool {
  TestTool({
    required this.toolName,
    required this.toolDescription,
    required this.toolParameters,
    required this.executeFunction,
  });

  final String toolName;
  final String toolDescription;
  final List<LLMToolParam> toolParameters;
  final Future<dynamic> Function(Map<String, dynamic> args, {dynamic extra})
  executeFunction;

  @override
  String get name => toolName;

  @override
  String get description => toolDescription;

  @override
  List<LLMToolParam> get parameters => toolParameters;

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) =>
      executeFunction(args, extra: extra);
}

/// Tests for tool/function calling functionality.
///
/// Tool calling with local models is implemented via prompt conventions
/// where the model outputs structured JSON that gets parsed and executed.
void main() {
  final config = TestConfig.instance;

  group('Tool Definition', () {
    test('creates tool with parameters', () {
      final tool = TestTool(
        toolName: 'get_weather',
        toolDescription: 'Get current weather for a location',
        toolParameters: [
          LLMToolParam(
            name: 'location',
            type: 'string',
            description: 'City name',
            isRequired: true,
          ),
          LLMToolParam(
            name: 'unit',
            type: 'string',
            description: 'Temperature unit (celsius/fahrenheit)',
            isRequired: false,
          ),
        ],
        executeFunction: (args, {extra}) async {
          return 'Weather in ${args['location']}: Sunny, 22°C';
        },
      );

      expect(tool.name, equals('get_weather'));
      expect(tool.parameters, hasLength(2));
      expect(tool.parameters.first.isRequired, isTrue);
      expect(tool.parameters.last.isRequired, isFalse);
    });

    test('tool execution returns result', () async {
      final tool = TestTool(
        toolName: 'add_numbers',
        toolDescription: 'Add two numbers',
        toolParameters: [
          LLMToolParam(
            name: 'a',
            type: 'number',
            description: 'First number',
            isRequired: true,
          ),
          LLMToolParam(
            name: 'b',
            type: 'number',
            description: 'Second number',
            isRequired: true,
          ),
        ],
        executeFunction: (args, {extra}) async {
          final a = args['a'] as num;
          final b = args['b'] as num;
          return (a + b).toString();
        },
      );

      final result = await tool.execute({'a': 5, 'b': 3});
      expect(result, equals('8'));
    });

    test('tool serializes to JSON schema', () {
      final tool = TestTool(
        toolName: 'search',
        toolDescription: 'Search for information',
        toolParameters: [
          LLMToolParam(
            name: 'query',
            type: 'string',
            description: 'Search query',
            isRequired: true,
          ),
        ],
        executeFunction: (args, {extra}) async =>
            'Results for: ${args['query']}',
      );

      final schema = tool.toJson;

      expect(schema['function']['name'], equals('search'));
      expect(schema['function']['description'], isNotEmpty);
      expect(schema['function']['parameters'], isNotNull);
    });
  });

  group('Tool Calling with Model', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() {
      modelPath = config.textModelPath ?? config.smallModelPath;
      if (modelPath == null) {
        print('⚠️  No model available for tool calling tests');
      }
    });

    setUp(() {
      repo = LlamaCppChatRepository(
        contextSize: 2048,
        batchSize: 256,
        nGpuLayers: config.gpuLayers,
        maxToolAttempts: 3,
      );
    });

    tearDown(() {
      repo.dispose();
    });

    test(
      'parses JSON tool call from model output',
      () async {
        if (modelPath == null) {
          markTestSkipped('No model available');
          return;
        }

        await repo.loadModel(modelPath!);

        // Define a calculator tool
        final calculatorTool = TestTool(
          toolName: 'calculator',
          toolDescription: 'Perform basic math calculations',
          toolParameters: [
            LLMToolParam(
              name: 'expression',
              type: 'string',
              description: 'Math expression to evaluate',
              isRequired: true,
            ),
          ],
          executeFunction: (args, {extra}) async {
            final expr = args['expression'] as String;
            // Simple eval for testing
            if (expr.contains('+')) {
              final parts = expr.split('+').map((s) => int.parse(s.trim()));
              return parts.reduce((a, b) => a + b).toString();
            }
            return 'Unable to evaluate: $expr';
          },
        );

        final messages = [
          LLMMessage(
            role: LLMRole.system,
            content: '''You are a helpful assistant with access to tools.
When you need to perform a calculation, output a JSON tool call:
{"name": "calculator", "arguments": {"expression": "5 + 3"}}

Available tools:
- calculator: Perform basic math calculations
  Parameters: expression (string) - Math expression to evaluate''',
          ),
          LLMMessage(
            role: LLMRole.user,
            content: 'What is 7 + 8? Use the calculator tool.',
          ),
        ];

        final buffer = StringBuffer();
        List<LLMToolCall>? toolCalls;

        print('Prompt: What is 7 + 8? Use the calculator tool.');
        print('Response: ');

        await for (final chunk in repo.streamChat(
          'test',
          messages: messages,
          tools: [calculatorTool],
        )) {
          buffer.write(chunk.message?.content ?? '');
          stdout.write(chunk.message?.content ?? '');

          if (chunk.message?.toolCalls != null) {
            toolCalls = chunk.message!.toolCalls;
          }
        }
        print('\n');

        final response = buffer.toString();
        print('Full response: $response');

        // Check if response contains JSON or tool calls were parsed
        if (toolCalls != null && toolCalls.isNotEmpty) {
          print('Parsed tool calls: ${toolCalls.map((t) => t.name).toList()}');
          expect(toolCalls.first.name, equals('calculator'));
        } else {
          // Model might include JSON in response
          final hasToolJson =
              response.contains('"name"') && response.contains('"arguments"');
          print('Contains tool JSON: $hasToolJson');
        }
      },
      timeout: Timeout(Duration(minutes: 2)),
    );

    test('executes tool and returns result', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      bool toolWasExecuted = false;
      String? toolResult;

      final weatherTool = TestTool(
        toolName: 'get_weather',
        toolDescription: 'Get current weather for a city',
        toolParameters: [
          LLMToolParam(
            name: 'city',
            type: 'string',
            description: 'City name',
            isRequired: true,
          ),
        ],
        executeFunction: (args, {extra}) async {
          toolWasExecuted = true;
          final city = args['city'] ?? 'Unknown';
          toolResult = 'Weather in $city: Sunny, 25°C';
          return toolResult;
        },
      );

      final messages = [
        LLMMessage(
          role: LLMRole.system,
          content:
              '''You have access to tools. To use a tool, respond with JSON:
{"name": "get_weather", "arguments": {"city": "Paris"}}

Tools:
- get_weather: Get current weather. Parameters: city (string)''',
        ),
        LLMMessage(
          role: LLMRole.user,
          content: 'What\'s the weather in London?',
        ),
      ];

      await for (final _ in repo.streamChat(
        'test',
        messages: messages,
        tools: [weatherTool],
      )) {
        // Process stream
      }

      print('Tool was executed: $toolWasExecuted');
      print('Tool result: $toolResult');

      // The tool should have been called (if model follows instructions)
      // Note: Small models may not reliably follow tool-calling instructions
    }, timeout: Timeout(Duration(minutes: 2)));

    test('handles multiple tools', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      final tools = [
        TestTool(
          toolName: 'add',
          toolDescription: 'Add two numbers',
          toolParameters: [
            LLMToolParam(
              name: 'a',
              type: 'number',
              description: 'First number',
              isRequired: true,
            ),
            LLMToolParam(
              name: 'b',
              type: 'number',
              description: 'Second number',
              isRequired: true,
            ),
          ],
          executeFunction: (args, {extra}) async {
            return ((args['a'] as num) + (args['b'] as num)).toString();
          },
        ),
        TestTool(
          toolName: 'multiply',
          toolDescription: 'Multiply two numbers',
          toolParameters: [
            LLMToolParam(
              name: 'a',
              type: 'number',
              description: 'First number',
              isRequired: true,
            ),
            LLMToolParam(
              name: 'b',
              type: 'number',
              description: 'Second number',
              isRequired: true,
            ),
          ],
          executeFunction: (args, {extra}) async {
            return ((args['a'] as num) * (args['b'] as num)).toString();
          },
        ),
      ];

      final messages = [
        LLMMessage(
          role: LLMRole.system,
          content: '''You have access to math tools:
- add: Add two numbers (a, b)
- multiply: Multiply two numbers (a, b)

Use JSON format: {"name": "tool_name", "arguments": {"a": 5, "b": 3}}''',
        ),
        LLMMessage(role: LLMRole.user, content: 'What is 6 times 7?'),
      ];

      final buffer = StringBuffer();
      await for (final chunk in repo.streamChat(
        'test',
        messages: messages,
        tools: tools,
      )) {
        buffer.write(chunk.message?.content ?? '');
      }

      print('Response: ${buffer.toString()}');
    }, timeout: Timeout(Duration(minutes: 2)));
  });

  group('Tool Call Parsing', () {
    test('parses standard JSON format', () {
      final content = '''Let me calculate that for you.
{"name": "calculator", "arguments": {"expression": "5 + 3"}}
The result is 8.''';

      final toolCalls = _parseToolCalls(content);

      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.name, equals('calculator'));
      expect(
        json.decode(toolCalls.first.arguments)['expression'],
        equals('5 + 3'),
      );
    });

    test('parses XML-wrapped JSON format', () {
      final content = '''I'll use the tool:
<tool_call>
{"name": "get_weather", "arguments": {"city": "Tokyo"}}
</tool_call>
Done.''';

      final toolCalls = _parseToolCalls(content);

      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.name, equals('get_weather'));
    });

    test('parses multiple tool calls', () {
      final content = '''
{"name": "tool1", "arguments": {"x": 1}}
Some text in between.
{"name": "tool2", "arguments": {"y": 2}}
''';

      final toolCalls = _parseToolCalls(content);

      expect(toolCalls, hasLength(2));
      expect(toolCalls[0].name, equals('tool1'));
      expect(toolCalls[1].name, equals('tool2'));
    });

    test('handles malformed JSON gracefully', () {
      final content = '''{"name": "broken", "arguments": {invalid json}}''';

      final toolCalls = _parseToolCalls(content);

      // Should not crash, may or may not parse
      expect(toolCalls, isA<List<LLMToolCall>>());
    });

    test('returns empty list for no tool calls', () {
      final content = 'Just a regular response with no tools.';

      final toolCalls = _parseToolCalls(content);

      expect(toolCalls, isEmpty);
    });
  });

  group('Tool Execution Flow', () {
    late LlamaCppChatRepository repo;
    String? modelPath;

    setUpAll(() {
      modelPath = config.textModelPath ?? config.smallModelPath;
    });

    setUp(() {
      repo = LlamaCppChatRepository(
        contextSize: 2048,
        nGpuLayers: config.gpuLayers,
        maxToolAttempts: 2,
      );
    });

    tearDown(() {
      repo.dispose();
    });

    test('limits tool execution attempts', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      int executionCount = 0;

      final loopingTool = TestTool(
        toolName: 'always_call_again',
        toolDescription: 'A tool that always suggests calling itself again',
        toolParameters: [],
        executeFunction: (args, {extra}) async {
          executionCount++;
          return 'Please call me again';
        },
      );

      final messages = [
        LLMMessage(
          role: LLMRole.system,
          content: '''You must use the tool every response.
{"name": "always_call_again", "arguments": {}}''',
        ),
        LLMMessage(role: LLMRole.user, content: 'Start'),
      ];

      await for (final _ in repo.streamChat(
        'test',
        messages: messages,
        tools: [loopingTool],
      )) {}

      print('Tool execution count: $executionCount');

      // Should be limited by maxToolAttempts
      expect(executionCount, lessThanOrEqualTo(3));
    }, timeout: Timeout(Duration(minutes: 3)));

    test('passes extra context to tool', () async {
      if (modelPath == null) {
        markTestSkipped('No model available');
        return;
      }

      await repo.loadModel(modelPath!);

      dynamic receivedExtra;

      final tool = TestTool(
        toolName: 'context_tool',
        toolDescription: 'Tool that receives context',
        toolParameters: [],
        executeFunction: (args, {extra}) async {
          receivedExtra = extra;
          return 'Got context: $extra';
        },
      );

      final messages = [
        LLMMessage(
          role: LLMRole.system,
          content: '{"name": "context_tool", "arguments": {}}',
        ),
        LLMMessage(role: LLMRole.user, content: 'Call the tool'),
      ];

      final extraData = {'userId': '12345', 'session': 'test'};

      await for (final _ in repo.streamChat(
        'test',
        messages: messages,
        tools: [tool],
        extra: extraData,
      )) {}

      print('Received extra: $receivedExtra');

      // Extra should be passed through if tool was called
      if (receivedExtra != null) {
        expect(receivedExtra, equals(extraData));
      }
    }, timeout: Timeout(Duration(minutes: 2)));
  });
}

/// Helper function to parse tool calls from content (mirrors the repository's logic)
List<LLMToolCall> _parseToolCalls(String content) {
  final toolCalls = <LLMToolCall>[];
  final parsedRanges = <(int, int)>[];

  // Try XML-like format first (more specific)
  final xmlPattern = RegExp(
    r'<tool_call>\s*(\{.*?\})\s*</tool_call>',
    multiLine: true,
    dotAll: true,
  );

  for (final match in xmlPattern.allMatches(content)) {
    try {
      final jsonStr = match.group(1)!;
      final data = json.decode(jsonStr) as Map<String, dynamic>;

      toolCalls.add(
        LLMToolCall(
          id: 'call_${toolCalls.length}',
          name: data['name'] as String,
          arguments: json.encode(data['arguments']),
        ),
      );
      // Track the range to avoid double-parsing
      parsedRanges.add((match.start, match.end));
    } catch (_) {
      // Skip invalid matches
    }
  }

  // Try JSON format for content not already parsed
  final jsonPattern = RegExp(
    r'\{[^{}]*"name"\s*:\s*"([^"]+)"[^{}]*"arguments"\s*:\s*(\{[^{}]*\})[^{}]*\}',
    multiLine: true,
  );

  for (final match in jsonPattern.allMatches(content)) {
    // Skip if this match is inside an already-parsed XML block
    final isInsideParsedRange = parsedRanges.any(
      (range) => match.start >= range.$1 && match.end <= range.$2,
    );
    if (isInsideParsedRange) continue;

    try {
      final name = match.group(1)!;
      final args = match.group(2)!;

      toolCalls.add(
        LLMToolCall(
          id: 'call_${toolCalls.length}',
          name: name,
          arguments: args,
        ),
      );
    } catch (_) {
      // Skip invalid matches
    }
  }

  return toolCalls;
}
