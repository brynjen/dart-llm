/// Ollama can answer `200`, open the stream and only then report a failure
/// in-band, as `{"error": "..."}`. That arrives after the send has returned, so
/// the retry around the send cannot see it.
///
/// Note what Ollama does **not** give us: its in-band error is a bare string
/// with no status code, unlike vLLM, OpenAI, Anthropic and Gemini, which all
/// carry one that `LLMApiException.statusCode` can be set from. Retryability
/// here therefore falls back to `ErrorHandlers.isRetryableError`'s message
/// heuristic. Inventing a code by scraping the text would be guessing, so a
/// model-not-found error stays non-retryable, as it should.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

/// Serves a scripted body per attempt.
class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.bodies);

  final List<String> bodies;
  int attempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = bodies[attempts.clamp(0, bodies.length - 1)];
    attempts++;
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}

Future<List<LLMChunk>> _run(_ScriptedClient client) =>
    OllamaChatRepository(
          httpClient: client,
          retryConfig: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration.zero,
          ),
        )
        .streamChat(
          'qwen3:0.6b',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        )
        .toList();

String _chunk(String content, {bool done = false}) =>
    '${json.encode({
      'model': 'm',
      'created_at': '2026-01-01T00:00:00Z',
      'message': {'role': 'assistant', 'content': content},
      'done': done,
    })}\n';

/// Classified retryable by message, which is the only route Ollama has.
const _transportError = '{"error":"connection reset by peer"}\n';
final _okBody = _chunk('ok', done: true);

const _modelMissing = '{"error":"model \'nope\' not found"}\n';

void main() {
  group('in-band errors', () {
    test('a retryable one before any output is retried and recovers', () async {
      final client = _ScriptedClient([
        _transportError,
        _chunk('ok', done: true),
      ]);

      final chunks = await _run(client);

      expect(client.attempts, 2, reason: 'the failed turn should be re-issued');
      expect(chunks, isNotEmpty);
    });

    test('a non-retryable one is surfaced immediately', () async {
      final client = _ScriptedClient([_modelMissing]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(
        client.attempts,
        1,
        reason: 'pulling the model is the fix, not a retry',
      );
    });

    test('one after output has been emitted is never retried', () async {
      // Re-running would deliver the turn's opening twice.
      final client = _ScriptedClient([
        _chunk('partial') + _transportError,
        _chunk('ok', done: true),
      ]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1, reason: 'output already reached the caller');
    });

    test('a healthy turn is sent exactly once', () async {
      final client = _ScriptedClient([_chunk('ok', done: true)]);

      await _run(client);

      expect(client.attempts, 1);
    });
  });

  group('retryable HTTP statuses on a streaming turn', () {
    test('a 503 response is retried and recovers', () async {
      // A non-2xx is a *returned* response, not a thrown error, so the retry
      // around the send never saw it — `RetryConfig.retryableStatusCodes` did
      // not apply to streaming at all and this failed on the first attempt.
      final client = _StatusScriptedClient([
        (503, '{"error":{"message":"overloaded"}}'),
        (200, _okBody),
      ]);

      final chunks = await _runStatus(client);

      expect(client.attempts, 2, reason: 'a retryable status must be retried');
      expect(chunks, isNotEmpty);
    });

    test('a 400 response is surfaced immediately', () async {
      final client = _StatusScriptedClient([
        (400, '{"error":{"message":"bad request"}}'),
      ]);

      await expectLater(_runStatus(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1);
    });
  });
}

/// Serves a scripted (status, body) per attempt.
class _StatusScriptedClient extends http.BaseClient {
  _StatusScriptedClient(this.responses);

  final List<(int, String)> responses;
  int attempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final (status, body) = responses[attempts.clamp(0, responses.length - 1)];
    attempts++;
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }
}

Future<List<LLMChunk>> _runStatus(_StatusScriptedClient client) =>
    OllamaChatRepository(
          httpClient: client,
          retryConfig: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration.zero,
          ),
        )
        .streamChat(
          'qwen3:0.6b',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        )
        .toList();
