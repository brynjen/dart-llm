/// Shared helpers, configuration, and test tools for Ollama integration tests.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

// ============================================================================
// Test Configuration
// ============================================================================

const baseUrl = 'http://192.168.0.74:11434';
const chatModel = 'gpt-oss:20b';
const embeddingModel = 'nomic-embed-text';

// ============================================================================
// Helper Utilities
// ============================================================================

/// Creates a test repository with default configuration.
OllamaChatRepository createRepository({
  String? customBaseUrl,
  TimeoutConfig? timeoutConfig,
  RetryConfig? retryConfig,
}) {
  return OllamaChatRepositoryBuilder()
      .baseUrl(customBaseUrl ?? baseUrl)
      .timeoutConfig(
        timeoutConfig ??
            const TimeoutConfig(
              connectionTimeout: Duration(seconds: 10),
              readTimeout: Duration(minutes: 2),
            ),
      )
      .retryConfig(retryConfig ?? const RetryConfig(maxAttempts: 3))
      .build();
}

/// Collects all chunks from a stream.
Future<List<LLMChunk>> collectStream(Stream<LLMChunk> stream) async {
  final chunks = <LLMChunk>[];
  await for (final chunk in stream) {
    chunks.add(chunk);
  }
  return chunks;
}

/// Waits for stream completion and collects chunks with timeout.
Future<List<LLMChunk>> collectStreamWithTimeout(
  Stream<LLMChunk> stream,
  Duration timeout,
) async {
  return await stream.timeout(timeout).toList();
}

/// Extracts accumulated content from chunks.
String extractContent(List<LLMChunk> chunks) {
  return chunks
      .map((chunk) => chunk.message?.content ?? '')
      .where((content) => content.isNotEmpty)
      .join();
}

/// Extracts accumulated thinking from chunks.
String extractThinking(List<LLMChunk> chunks) {
  return chunks
      .map((chunk) => chunk.message?.thinking ?? '')
      .where((thinking) => thinking.isNotEmpty)
      .join();
}

/// Verifies chunk structure is valid.
void verifyChunkStructure(LLMChunk chunk) {
  expect(chunk.model, isNotNull, reason: 'Chunk model should not be null');
  expect(chunk.model, isNotEmpty, reason: 'Chunk model should not be empty');
  expect(
    chunk.createdAt,
    isNotNull,
    reason: 'Chunk createdAt should not be null',
  );
  expect(
    chunk.createdAt,
    isA<DateTime>(),
    reason: 'Chunk createdAt should be a DateTime',
  );
}

/// Verifies response structure is valid.
void verifyResponseStructure(LLMResponse response) {
  expect(response.done, isTrue, reason: 'Response should be done');
  expect(
    response.content,
    isNotNull,
    reason: 'Response content should not be null',
  );
  expect(
    response.model,
    isNotNull,
    reason: 'Response model should not be null',
  );
  expect(
    response.model,
    isNotEmpty,
    reason: 'Response model should not be empty',
  );
  expect(
    response.role,
    equals('assistant'),
    reason: 'Response role should be assistant',
  );
  expect(
    response.createdAt,
    isNotNull,
    reason: 'Response createdAt should not be null',
  );
  expect(
    response.createdAt,
    isA<DateTime>(),
    reason: 'Response createdAt should be a DateTime',
  );
  expect(
    response.doneReason,
    isNotNull,
    reason: 'Response doneReason should not be null',
  );
  expect(
    response.doneReason,
    isNotEmpty,
    reason: 'Response doneReason should not be empty',
  );
  expect(
    response.promptEvalCount,
    greaterThanOrEqualTo(0),
    reason: 'Response promptEvalCount should be non-negative',
  );
  expect(
    response.evalCount,
    greaterThanOrEqualTo(0),
    reason: 'Response evalCount should be non-negative',
  );
}

/// Calculates cosine similarity between two vectors.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError('Vectors must have the same length');
  }
  double dotProduct = 0.0;
  double normA = 0.0;
  double normB = 0.0;
  for (int i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0.0 || normB == 0.0) return 0.0;
  return dotProduct / (sqrt(normA) * sqrt(normB));
}

// ============================================================================
// Test Tool Implementations
// ============================================================================

/// Calculator tool for testing basic arithmetic operations.
class CalculatorTool extends LLMTool {
  @override
  String get name => 'calculator';

  @override
  String get description =>
      'Performs basic arithmetic operations (addition, subtraction, multiplication, division)';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'expression',
      type: 'string',
      description:
          'The arithmetic expression to evaluate (e.g., "2 + 2", "10 * 5")',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    final expression = args['expression'] as String;
    // Simple arithmetic evaluator (for testing purposes)
    try {
      // Remove spaces and evaluate
      final cleanExpr = expression.replaceAll(' ', '');
      final result = _evaluateExpression(cleanExpr);
      return 'Result: $result';
    } catch (e) {
      return 'Error: Invalid expression - $e';
    }
  }

  double _evaluateExpression(String expr) {
    // Very simple evaluator for testing - handles basic operations
    if (expr.contains('+')) {
      final parts = expr.split('+');
      return parts.map((p) => double.parse(p)).reduce((a, b) => a + b);
    } else if (expr.contains('-')) {
      final parts = expr.split('-');
      return parts.map((p) => double.parse(p)).reduce((a, b) => a - b);
    } else if (expr.contains('*')) {
      final parts = expr.split('*');
      return parts.map((p) => double.parse(p)).reduce((a, b) => a * b);
    } else if (expr.contains('/')) {
      final parts = expr.split('/');
      return parts.map((p) => double.parse(p)).reduce((a, b) => a / b);
    } else {
      return double.parse(expr);
    }
  }
}

/// Weather tool for testing with mock data.
class WeatherTool extends LLMTool {
  @override
  String get name => 'get_weather';

  @override
  String get description => 'Gets the current weather for a given location';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'location',
      type: 'string',
      description: 'The city or location name',
      isRequired: true,
    ),
    LLMToolParam(
      name: 'unit',
      type: 'string',
      description: 'Temperature unit: celsius or fahrenheit',
      isRequired: false,
      enums: ['celsius', 'fahrenheit'],
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    final location = args['location'] as String;
    final unit = args['unit'] as String? ?? 'celsius';
    // Mock weather data
    return jsonEncode({
      'location': location,
      'temperature': unit == 'fahrenheit' ? 72 : 22,
      'unit': unit,
      'condition': 'sunny',
      'humidity': 65,
    });
  }
}

/// Echo tool that returns input as output.
class EchoTool extends LLMTool {
  @override
  String get name => 'echo';

  @override
  String get description => 'Echoes back the input message';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'message',
      type: 'string',
      description: 'The message to echo back',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return args['message'] as String;
  }
}

/// Tool that always throws an error for testing error handling.
class ErrorTool extends LLMTool {
  @override
  String get name => 'error_tool';

  @override
  String get description =>
      'A tool that always throws an error for testing purposes';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'should_error',
      type: 'boolean',
      description: 'Whether to throw an error',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    throw Exception('Intentional error for testing');
  }
}

/// Tool that simulates slow execution.
class SlowTool extends LLMTool {
  @override
  String get name => 'slow_tool';

  @override
  String get description => 'A tool that takes a long time to execute';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'delay_seconds',
      type: 'integer',
      description: 'Number of seconds to delay',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    final delay = args['delay_seconds'] as int;
    await Future.delayed(Duration(seconds: delay));
    return 'Completed after $delay seconds';
  }
}

/// Search tool for testing multiple tools.
class SearchTool extends LLMTool {
  @override
  String get name => 'search';

  @override
  String get description => 'Searches for information on a given topic';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'query',
      type: 'string',
      description: 'The search query',
      isRequired: true,
    ),
    LLMToolParam(
      name: 'limit',
      type: 'integer',
      description: 'Maximum number of results',
      isRequired: false,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    final query = args['query'] as String;
    final limit = args['limit'] as int? ?? 5;
    return jsonEncode({
      'query': query,
      'results': List.generate(limit, (i) => 'Result ${i + 1} for "$query"'),
      'count': limit,
    });
  }
}

/// Tool with no parameters.
class NoParamTool extends LLMTool {
  @override
  String get name => 'get_time';

  @override
  String get description => 'Gets the current time';

  @override
  List<LLMToolParam> get parameters => [];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return DateTime.now().toIso8601String();
  }
}

/// Tool with complex nested parameters.
class ComplexTool extends LLMTool {
  @override
  String get name => 'complex_tool';

  @override
  String get description => 'A tool with complex nested parameters';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'config',
      type: 'object',
      description: 'Configuration object',
      isRequired: true,
      properties: [
        LLMToolParam(
          name: 'items',
          type: 'array',
          description: 'Array of items',
          items: LLMToolParam(
            name: 'item',
            type: 'string',
            description: 'An item',
          ),
        ),
        LLMToolParam(
          name: 'enabled',
          type: 'boolean',
          description: 'Whether enabled',
          isRequired: true,
        ),
      ],
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return jsonEncode({'processed': true, 'config': args['config']});
  }
}
