import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('LLMToolCall', () {
    test('construction with all fields', () {
      final toolCall = LLMToolCall(
        id: 'call_123',
        name: 'calculator',
        arguments: '{"a": 2, "b": 2}',
      );

      expect(toolCall.id, 'call_123');
      expect(toolCall.name, 'calculator');
      expect(toolCall.arguments, '{"a": 2, "b": 2}');
    });

    test('construction with null ID', () {
      final toolCall = LLMToolCall(
        id: null,
        name: 'calculator',
        arguments: '{"a": 2, "b": 2}',
      );

      expect(toolCall.id, null);
      expect(toolCall.name, 'calculator');
      expect(toolCall.arguments, '{"a": 2, "b": 2}');
    });

    test('construction with empty arguments', () {
      final toolCall = LLMToolCall(
        id: 'call_1',
        name: 'tool',
        arguments: '{}',
      );

      expect(toolCall.arguments, '{}');
    });

    test('construction with complex JSON arguments', () {
      final toolCall = LLMToolCall(
        id: 'call_1',
        name: 'complex',
        arguments: '{"nested": {"value": 42}, "array": [1, 2, 3]}',
      );

      expect(toolCall.arguments, '{"nested": {"value": 42}, "array": [1, 2, 3]}');
    });
  });
}
