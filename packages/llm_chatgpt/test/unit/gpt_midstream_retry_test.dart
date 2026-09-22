/// A provider can answer `200`, open the stream and only then report a failure
/// in-band. That error arrives after the send has returned, so the retry around
/// the send cannot see it. This pins that llm_chatgpt re-issues such a turn while
/// nothing has reached the caller, and never once it has.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_chatgpt/llm_chatgpt.dart';
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
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

Future<List<LLMChunk>> _run(_ScriptedClient client) =>
    ChatGPTChatRepository(
          apiKey: 'k',
          httpClient: client,
          retryConfig: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration.zero,
          ),
        )
        .streamChat(
          'gpt-4o',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        )
        .toList();

void main() {
  group('in-band errors', () {
    test('a retryable one before any output is retried and recovers', () async {
      final client = _ScriptedClient([_errorFrame, _okBody]);

      final chunks = await _run(client);

      expect(client.attempts, 2, reason: 'the failed turn should be re-issued');
      expect(chunks, isNotEmpty);
    });

    test('one after output has been emitted is never retried', () async {
      // Re-running would deliver the turn's opening twice.
      final client = _ScriptedClient([_partialThenError, _okBody]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1, reason: 'output already reached the caller');
    });

    test('a healthy turn is sent exactly once', () async {
      final client = _ScriptedClient([_okBody]);

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

const _errorFrame = 'data: {"error":{"message":"overloaded","code":503}}\n\n';

const _okBody =
    'data: {"id":"c1","created":1700000000,"model":"m","choices":'
    '[{"index":0,"delta":{"role":"assistant","content":"ok"},'
    '"finish_reason":"stop"}]}\n\n'
    'data: [DONE]\n\n';

const _partialThenError =
    'data: {"id":"c1","created":1700000000,"model":"m","choices":'
    '[{"index":0,"delta":{"role":"assistant","content":"partial"},'
    '"finish_reason":null}]}\n\n'
    'data: {"error":{"message":"overloaded","code":503}}\n\n';

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
    ChatGPTChatRepository(
          apiKey: 'k',
          httpClient: client,
          retryConfig: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration.zero,
          ),
        )
        .streamChat(
          'gpt-4o',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        )
        .toList();
