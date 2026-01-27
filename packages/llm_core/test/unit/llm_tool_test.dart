import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

class TestTool extends LLMTool {
  TestTool({
    required this.toolName,
    required this.toolDescription,
    required this.toolParameters,
  });

  final String toolName;
  final String toolDescription;
  final List<LLMToolParam> toolParameters;

  @override
  String get name => toolName;

  @override
  String get description => toolDescription;

  @override
  List<LLMToolParam> get parameters => toolParameters;

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return 'result';
  }
}

void main() {
  group('LLMTool.toJson', () {
    test('tool with no parameters', () {
      final tool = TestTool(
        toolName: 'get_time',
        toolDescription: 'Gets the current time',
        toolParameters: [],
      );

      final json = tool.toJson;

      expect(json['type'], 'function');
      expect(json['function']['name'], 'get_time');
      expect(json['function']['description'], 'Gets the current time');
      expect(json['function'].containsKey('parameters'), false);
    });

    test('tool with single required parameter', () {
      final tool = TestTool(
        toolName: 'calculator',
        toolDescription: 'Performs calculations',
        toolParameters: [
          LLMToolParam(
            name: 'expression',
            type: 'string',
            description: 'Math expression',
            isRequired: true,
          ),
        ],
      );

      final json = tool.toJson;

      expect(json['function']['name'], 'calculator');
      expect(json['function']['parameters'], isA<Map>());
      expect(json['function']['parameters']['type'], 'object');
      expect(
        json['function']['parameters']['properties']['expression']['type'],
        'string',
      );
      expect(json['function']['parameters']['required'], ['expression']);
    });

    test('tool with optional parameter', () {
      final tool = TestTool(
        toolName: 'search',
        toolDescription: 'Searches',
        toolParameters: [
          LLMToolParam(
            name: 'query',
            type: 'string',
            description: 'Search query',
            isRequired: true,
          ),
          LLMToolParam(
            name: 'limit',
            type: 'integer',
            description: 'Result limit',
          ),
        ],
      );

      final json = tool.toJson;

      expect(json['function']['parameters']['required'], ['query']);
      expect(
        json['function']['parameters']['required'].contains('limit'),
        false,
      );
    });

    test('tool with all optional parameters', () {
      final tool = TestTool(
        toolName: 'optional',
        toolDescription: 'All optional',
        toolParameters: [
          LLMToolParam(name: 'param1', type: 'string', description: 'Param 1'),
          LLMToolParam(name: 'param2', type: 'integer', description: 'Param 2'),
        ],
      );

      final json = tool.toJson;

      expect(json['function']['parameters'].containsKey('required'), false);
    });

    test('tool with complex nested parameters', () {
      final tool = TestTool(
        toolName: 'complex',
        toolDescription: 'Complex tool',
        toolParameters: [
          LLMToolParam(
            name: 'config',
            type: 'object',
            description: 'Configuration',
            isRequired: true,
            properties: [
              LLMToolParam(
                name: 'items',
                type: 'array',
                description: 'Items',
                items: LLMToolParam(
                  name: 'item',
                  type: 'string',
                  description: 'Item',
                ),
              ),
            ],
          ),
        ],
      );

      final json = tool.toJson;

      expect(
        json['function']['parameters']['properties']['config']['type'],
        'object',
      );
      expect(
        json['function']['parameters']['properties']['config']['properties']['items']['type'],
        'array',
      );
    });
  });

  group('LLMTool.llmDescription', () {
    test('generates correct description format', () {
      final tool = TestTool(
        toolName: 'calculator',
        toolDescription: 'Performs calculations',
        toolParameters: [],
      );

      expect(tool.llmDescription, '- calculator: Performs calculations');
    });
  });
}
