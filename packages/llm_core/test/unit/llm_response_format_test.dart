import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('JsonFormat', () {
    test('is const-constructible', () {
      const format = JsonFormat();
      expect(format, isA<JsonFormat>());
      expect(format, isA<LLMResponseFormat>());
    });

    test('can be used in const StreamChatOptions', () {
      const options = StreamChatOptions(responseFormat: JsonFormat());
      expect(options.responseFormat, isA<JsonFormat>());
    });

    test('two instances are equal via identity', () {
      const a = JsonFormat();
      const b = JsonFormat();
      // const canonicalisation means they're the same object
      expect(identical(a, b), isTrue);
    });
  });

  group('JsonSchemaFormat', () {
    test('is const-constructible with required fields', () {
      const format = JsonSchemaFormat(
        name: 'User',
        schema: {'type': 'object'},
      );
      expect(format, isA<JsonSchemaFormat>());
      expect(format, isA<LLMResponseFormat>());
      expect(format.name, 'User');
      expect(format.schema, {'type': 'object'});
      expect(format.strict, isTrue); // default
    });

    test('strict defaults to true', () {
      const format = JsonSchemaFormat(
        name: 'Test',
        schema: {'type': 'string'},
      );
      expect(format.strict, isTrue);
    });

    test('strict can be set to false', () {
      const format = JsonSchemaFormat(
        name: 'Test',
        schema: {'type': 'string'},
        strict: false,
      );
      expect(format.strict, isFalse);
    });

    test('can be used in const StreamChatOptions', () {
      const options = StreamChatOptions(
        responseFormat: JsonSchemaFormat(
          name: 'User',
          schema: {'type': 'object', 'properties': {}},
        ),
      );
      final format = options.responseFormat as JsonSchemaFormat;
      expect(format.name, 'User');
    });
  });

  group('LLMResponseFormat pattern matching', () {
    test('switch is exhaustive without default case', () {
      // This verifies the sealed class pattern works for switch
      LLMResponseFormat format = const JsonFormat();
      final result = switch (format) {
        JsonFormat() => 'json',
        JsonSchemaFormat() => 'schema',
      };
      expect(result, 'json');

      format = const JsonSchemaFormat(name: 'X', schema: {});
      // Re-declare as base type so the switch exhaustively covers both arms.
      final LLMResponseFormat format2 = format;
      final result2 = switch (format2) {
        JsonFormat() => 'json',
        JsonSchemaFormat() => 'schema',
      };
      expect(result2, 'schema');
    });

    test('JsonSchemaFormat carries payload through switch', () {
      const format = JsonSchemaFormat(
        name: 'MySchema',
        schema: {'type': 'object', 'properties': {'id': {'type': 'integer'}}},
        strict: false,
      );

      const LLMResponseFormat base = format;
      final name = switch (base) {
        JsonFormat() => 'no name',
        JsonSchemaFormat() => base.name,
      };
      expect(name, 'MySchema');
    });
  });

  group('StreamChatOptions.responseFormat', () {
    test('defaults to null', () {
      const options = StreamChatOptions();
      expect(options.responseFormat, isNull);
    });

    test('copyWith sets responseFormat', () {
      const original = StreamChatOptions();
      final updated = original.copyWith(responseFormat: const JsonFormat());
      expect(original.responseFormat, isNull);
      expect(updated.responseFormat, isA<JsonFormat>());
    });

    test('copyWith preserves responseFormat when not specified', () {
      const format = JsonFormat();
      const original = StreamChatOptions(responseFormat: format);
      final updated = original.copyWith(think: true);
      expect(updated.responseFormat, isA<JsonFormat>());
    });

    test('copyWith replaces responseFormat when specified', () {
      const original = StreamChatOptions(responseFormat: JsonFormat());
      final updated = original.copyWith(
        responseFormat: const JsonSchemaFormat(name: 'X', schema: {}),
      );
      expect(updated.responseFormat, isA<JsonSchemaFormat>());
    });
  });

  group('StreamChatOptionsMerger.responseFormat', () {
    test('is null by default', () {
      final merged = StreamChatOptionsMerger.merge();
      expect(merged.responseFormat, isNull);
    });

    test('inline responseFormat is used when options is null', () {
      final merged = StreamChatOptionsMerger.merge(
        responseFormat: const JsonFormat(),
      );
      expect(merged.responseFormat, isA<JsonFormat>());
    });

    test('options.responseFormat takes precedence over inline', () {
      final merged = StreamChatOptionsMerger.merge(
        responseFormat: const JsonFormat(),
        options: const StreamChatOptions(
          responseFormat: JsonSchemaFormat(name: 'X', schema: {}),
        ),
      );
      expect(merged.responseFormat, isA<JsonSchemaFormat>());
    });

    test('options with null responseFormat falls back to inline', () {
      // options present but responseFormat not set → falls back to inline
      final merged = StreamChatOptionsMerger.merge(
        responseFormat: const JsonFormat(),
        options: const StreamChatOptions(),
      );
      expect(merged.responseFormat, isA<JsonFormat>());
    });
  });
}
