import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('LLMToolResult.from', () {
    // These four cases pin the behavior callers had before this type existed,
    // so returning a plain value from `execute` is unchanged.
    test('passes an LLMToolResult through untouched', () {
      const original = LLMToolResult(
        content: 'ok',
        isError: true,
        metadata: {'exit_code': 2},
      );

      expect(
        identical(LLMToolResult.from(original, toolName: 'x'), original),
        isTrue,
      );
    });

    test('uses a String as the content verbatim', () {
      final result = LLMToolResult.from('42', toolName: 'calc');

      expect(result.content, '42');
      expect(result.isError, isFalse);
      expect(result.metadata, isEmpty);
    });

    test('keeps the exact legacy wording for null', () {
      final result = LLMToolResult.from(null, toolName: 'calc');

      expect(result.content, 'Tool calc returned null');
      expect(result.isError, isFalse);
    });

    test('stringifies anything else', () {
      final result = LLMToolResult.from({'a': 1}, toolName: 'calc');

      expect(result.content, '{a: 1}');
      expect(result.isError, isFalse);
    });
  });

  group('LLMToolResult', () {
    test('defaults to a successful, bare result', () {
      const result = LLMToolResult(content: 'done');

      expect(result.isError, isFalse);
      expect(result.metadata, isEmpty);
      expect(result.contentParts, isEmpty);
    });

    test('failure sets the error flag', () {
      const result = LLMToolResult.failure('boom', metadata: {'code': 1});

      expect(result.isError, isTrue);
      expect(result.content, 'boom');
      expect(result.metadata, {'code': 1});
    });

    test('carries content parts for providers that accept them', () {
      const result = LLMToolResult(
        content: 'a screenshot of the page',
        contentParts: [
          LLMTextContent('a screenshot of the page'),
          LLMImageContent('iVBORw0KGgo='),
        ],
      );

      expect(result.contentParts, hasLength(2));
      // Text stays required even with parts, because most providers only
      // accept text in a tool result and fall back to it.
      expect(result.content, isNotEmpty);
    });

    test('copyWith replaces only what it is given', () {
      const result = LLMToolResult(content: 'a', metadata: {'k': 'v'});

      final flagged = result.copyWith(isError: true);

      expect(flagged.isError, isTrue);
      expect(flagged.content, 'a');
      expect(flagged.metadata, {'k': 'v'});
    });

    test('toString names the failure and omits empty metadata', () {
      expect(
        const LLMToolResult(content: 'a').toString(),
        'LLMToolResult(isError: false, content: a)',
      );
      expect(
        const LLMToolResult.failure('b', metadata: {'x': 1}).toString(),
        contains('metadata: {x: 1}'),
      );
    });
  });
}
