/// Tests for the 400-translation table in [VLLMErrorHandler].
///
/// These errors only occur against a live server, so without unit coverage
/// the whole table is exercised by nothing in CI. Each case pins that a raw
/// vLLM error body is translated into the domain exception a caller can act
/// on — the exact failure mode the handler exists to prevent is a user
/// staring at `Bad request` when the real problem is a missing server flag.
library;

import 'dart:convert';

import 'package:llm_vllm/llm_vllm.dart';
import 'package:llm_vllm/src/vllm_error_handler.dart';
import 'package:test/test.dart';

String _errorBody(String message) => json.encode({
  'error': {'message': message, 'type': 'BadRequestError', 'code': 400},
});

Future<void> _handle(
  String errorBody, {
  bool thinkRequested = false,
  bool toolsRequested = false,
}) => VLLMErrorHandler.handleBadRequestError(
  errorBody: errorBody,
  model: 'test-model',
  thinkRequested: thinkRequested,
  toolsRequested: toolsRequested,
);

void main() {
  group('VLLMErrorHandler.handleBadRequestError', () {
    test('thinking-not-supported becomes ThinkingNotSupportedException', () {
      expect(
        () => _handle(
          _errorBody('Model does not support thinking'),
          thinkRequested: true,
        ),
        throwsA(isA<ThinkingNotSupportedException>()),
      );
    });

    test('thinking message without think requested stays generic', () {
      // The model-capability translation only applies when the caller asked
      // for the feature; otherwise the message is about something else.
      expect(
        () => _handle(_errorBody('Model does not support thinking')),
        throwsA(
          isA<LLMApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('tools-not-supported becomes ToolsNotSupportedException', () {
      expect(
        () => _handle(
          _errorBody('Model does not support tools'),
          toolsRequested: true,
        ),
        throwsA(isA<ToolsNotSupportedException>()),
      );
    });

    test('missing --tool-call-parser is restated as server config', () {
      // vLLM's message names the flag but reads like a request error; the
      // handler restates it as the configuration problem it is, including
      // the restart instructions.
      expect(
        () => _handle(
          _errorBody(
            '"auto" tool choice requires --enable-auto-tool-choice and '
            '--tool-call-parser to be set',
          ),
        ),
        throwsA(
          isA<ToolsNotSupportedException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('--enable-auto-tool-choice'),
              contains('--tool-call-parser'),
              contains('Original error:'),
            ),
          ),
        ),
      );
    });

    test('missing --reasoning-parser is restated as server config', () {
      expect(
        () => _handle(
          _errorBody('thinking_token_budget requires --reasoning-parser'),
        ),
        throwsA(
          isA<ThinkingNotSupportedException>().having(
            (e) => e.message,
            'message',
            allOf(contains('--reasoning-parser'), contains('Original error:')),
          ),
        ),
      );
    });

    test('does-not-support-chat names the model and the fix', () {
      expect(
        () => _handle(_errorBody('This model does not support chat')),
        throwsA(
          isA<LLMApiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('test-model'), contains('does not support chat')),
          ),
        ),
      );
    });

    test('unrecognized message passes through with the original text', () {
      expect(
        () => _handle(_errorBody('max_tokens must be at least 1')),
        throwsA(
          isA<LLMApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having(
                (e) => e.message,
                'message',
                contains('max_tokens must be at least 1'),
              ),
        ),
      );
    });

    test('string-valued error field is handled like a message', () {
      expect(
        () => _handle(
          json.encode({'error': 'Model does not support tools'}),
          toolsRequested: true,
        ),
        throwsA(isA<ToolsNotSupportedException>()),
      );
    });

    test('non-JSON body falls back to a generic 400', () {
      expect(
        () => _handle('<html>502 Bad Gateway</html>'),
        throwsA(
          isA<LLMApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having(
                (e) => e.responseBody,
                'responseBody',
                contains('502 Bad Gateway'),
              ),
        ),
      );
    });

    test('JSON body without an error field falls back gracefully', () {
      expect(
        () => _handle(json.encode({'detail': 'something else'})),
        throwsA(
          isA<LLMApiException>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });
}
