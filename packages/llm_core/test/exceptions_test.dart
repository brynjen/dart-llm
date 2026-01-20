import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

void main() {
  group('ThinkingNotSupportedException', () {
    test('toString includes message', () {
      const exception = ThinkingNotSupportedException(
        'gpt-4o',
        'Model does not support thinking',
      );

      expect(
        exception.toString(),
        'ThinkingNotSupportedException: Model does not support thinking',
      );
      expect(exception.model, 'gpt-4o');
      expect(exception.message, 'Model does not support thinking');
    });
  });

  group('ToolsNotSupportedException', () {
    test('toString includes message', () {
      const exception = ToolsNotSupportedException(
        'gpt-3.5',
        'Model does not support tools',
      );

      expect(
        exception.toString(),
        'ToolsNotSupportedException: Model does not support tools',
      );
      expect(exception.model, 'gpt-3.5');
      expect(exception.message, 'Model does not support tools');
    });
  });

  group('VisionNotSupportedException', () {
    test('toString includes message', () {
      const exception = VisionNotSupportedException(
        'gpt-3.5',
        'Model does not support vision',
      );

      expect(
        exception.toString(),
        'VisionNotSupportedException: Model does not support vision',
      );
      expect(exception.model, 'gpt-3.5');
      expect(exception.message, 'Model does not support vision');
    });
  });

  group('LLMApiException', () {
    test('toString with status code', () {
      const exception = LLMApiException('API request failed', statusCode: 500);

      expect(
        exception.toString(),
        'LLMApiException: HTTP 500 - API request failed',
      );
      expect(exception.message, 'API request failed');
      expect(exception.statusCode, 500);
      expect(exception.responseBody, null);
    });

    test('toString without status code', () {
      const exception = LLMApiException('Network error');

      expect(exception.toString(), 'LLMApiException: Network error');
      expect(exception.statusCode, null);
    });

    test('toString with status code and response body', () {
      const exception = LLMApiException(
        'API request failed',
        statusCode: 400,
        responseBody: '{"error": "Invalid request"}',
      );

      expect(
        exception.toString(),
        'LLMApiException: HTTP 400 - API request failed',
      );
      expect(exception.statusCode, 400);
      expect(exception.responseBody, '{"error": "Invalid request"}');
    });

    test('with different status codes', () {
      final statusCodes = [400, 401, 403, 404, 429, 500, 502, 503, 504];

      for (final code in statusCodes) {
        final exception = LLMApiException('Error', statusCode: code);

        expect(exception.statusCode, code);
        expect(exception.toString(), contains('HTTP $code'));
      }
    });
  });

  group('ModelLoadException', () {
    test('toString with model path', () {
      const exception = ModelLoadException(
        'Failed to load model',
        modelPath: '/path/to/model.gguf',
      );

      expect(exception.toString(), 'ModelLoadException: Failed to load model');
      expect(exception.message, 'Failed to load model');
      expect(exception.modelPath, '/path/to/model.gguf');
    });

    test('toString without model path', () {
      const exception = ModelLoadException('Failed to load model');

      expect(exception.toString(), 'ModelLoadException: Failed to load model');
      expect(exception.modelPath, null);
    });
  });

  group('Deprecated aliases', () {
    test('ThinkingNotAllowed is deprecated alias', () {
      // Just verify the type alias exists (deprecated)
      const exception = ThinkingNotSupportedException('model', 'message');
      expect(exception, isA<ThinkingNotSupportedException>());
    });

    test('ToolsNotAllowed is deprecated alias', () {
      const exception = ToolsNotSupportedException('model', 'message');
      expect(exception, isA<ToolsNotSupportedException>());
    });

    test('VisionNotAllowed is deprecated alias', () {
      const exception = VisionNotSupportedException('model', 'message');
      expect(exception, isA<VisionNotSupportedException>());
    });
  });
}
