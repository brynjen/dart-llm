import 'package:llm_claude/llm_claude.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudeUsage', () {
    test('fromJson with all fields', () {
      final usage = ClaudeUsage.fromJson({
        'input_tokens': 10,
        'output_tokens': 20,
      });

      expect(usage.inputTokens, 10);
      expect(usage.outputTokens, 20);
    });

    test('fromJson with missing fields defaults to 0', () {
      final usage = ClaudeUsage.fromJson({});

      expect(usage.inputTokens, 0);
      expect(usage.outputTokens, 0);
    });

    test('fromJson with null values defaults to 0', () {
      final usage = ClaudeUsage.fromJson({
        'input_tokens': null,
        'output_tokens': null,
      });

      expect(usage.inputTokens, 0);
      expect(usage.outputTokens, 0);
    });

    test('fromJson handles numeric types', () {
      final usage = ClaudeUsage.fromJson({
        'input_tokens': 100.0,
        'output_tokens': 200.0,
      });

      expect(usage.inputTokens, 100);
      expect(usage.outputTokens, 200);
    });
  });

  group('ClaudeChunk', () {
    test('creates with all fields', () {
      final now = DateTime.now();
      final chunk = ClaudeChunk(
        model: 'claude-opus-4-6',
        done: true,
        createdAt: now,
        promptEvalCount: 10,
        evalCount: 20,
      );

      expect(chunk.model, 'claude-opus-4-6');
      expect(chunk.done, isTrue);
      expect(chunk.createdAt, now);
      expect(chunk.promptEvalCount, 10);
      expect(chunk.evalCount, 20);
    });

    test('creates with default values', () {
      final chunk = ClaudeChunk();

      expect(chunk.model, isNull);
      expect(chunk.done, isNull);
      expect(chunk.message, isNull);
      expect(chunk.promptEvalCount, isNull);
      expect(chunk.evalCount, isNull);
    });

    test('is an LLMChunk', () {
      final chunk = ClaudeChunk(model: 'claude-opus-4-6');
      expect(chunk, isA<LLMChunk>());
    });
  });

  group('ClaudeToolUseBlock', () {
    test('creates with required fields', () {
      final block = ClaudeToolUseBlock(id: 'tu_123', name: 'calculator');

      expect(block.id, 'tu_123');
      expect(block.name, 'calculator');
      expect(block.inputJson, '');
    });

    test('creates with custom inputJson', () {
      final block = ClaudeToolUseBlock(
        id: 'tu_456',
        name: 'weather',
        inputJson: '{"location": "Paris"}',
      );

      expect(block.id, 'tu_456');
      expect(block.name, 'weather');
      expect(block.inputJson, '{"location": "Paris"}');
    });

    test('inputJson is mutable for accumulation', () {
      final block = ClaudeToolUseBlock(id: 'tu_789', name: 'search');
      block.inputJson = '{"query":';
      block.inputJson += '"test"}';

      expect(block.inputJson, '{"query":"test"}');
    });
  });
}
