/// Retryable failures on a streaming turn, by the two routes they arrive on.
///
/// A non-2xx is a *returned* response, not a thrown error, so the retry around
/// the send never saw it — `RetryConfig.retryableStatusCodes` did not apply to
/// streaming at all and a 529 failed on the first attempt. Anthropic can also
/// answer `200` and report the overload in-band, as an `error` event, which
/// arrives after the send has returned. Both are now retried, and only while
/// nothing has reached the caller.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_claude/llm_claude.dart';
import 'package:test/test.dart';

String _sse(String event, Map<String, dynamic> data) =>
    'event: $event\ndata: ${json.encode(data)}\n\n';

final _okBody =
    _sse('message_start', {
      'message': {
        'model': 'claude-opus-4-6',
        'usage': {'input_tokens': 10},
      },
    }) +
    _sse('content_block_start', {
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    }) +
    _sse('content_block_delta', {
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'ok'},
    }) +
    _sse('content_block_stop', {'index': 0}) +
    _sse('message_delta', {
      'delta': {'stop_reason': 'end_turn'},
      'usage': {'output_tokens': 2},
    }) +
    _sse('message_stop', <String, dynamic>{});

final _overloaded = _sse('error', {
  'type': 'error',
  'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
});

final _partialThenOverloaded =
    _sse('message_start', {
      'message': {
        'model': 'claude-opus-4-6',
        'usage': {'input_tokens': 10},
      },
    }) +
    _sse('content_block_start', {
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    }) +
    _sse('content_block_delta', {
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'partial'},
    }) +
    _overloaded;

/// Serves a scripted (status, body) per attempt.
class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.responses);

  final List<(int, String)> responses;
  int attempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final (status, body) = responses[attempts.clamp(0, responses.length - 1)];
    attempts++;
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }
}

Future<List<LLMChunk>> _run(_ScriptedClient client) =>
    ClaudeChatRepository(
          apiKey: 'k',
          httpClient: client,
          retryConfig: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration.zero,
          ),
        )
        .streamChat(
          'claude-opus-4-6',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        )
        .toList();

void main() {
  group('retryable failures on a streaming turn', () {
    test('a 529 response is retried and recovers', () async {
      final client = _ScriptedClient([
        (529, '{"type":"error","error":{"type":"overloaded_error"}}'),
        (200, _okBody),
      ]);

      final chunks = await _run(client);

      expect(client.attempts, 2, reason: 'a retryable status must be retried');
      expect(chunks.map((c) => c.message?.content ?? '').join(), 'ok');
    });

    test('an in-band overload before any output is retried', () async {
      final client = _ScriptedClient([(200, _overloaded), (200, _okBody)]);

      final chunks = await _run(client);

      expect(client.attempts, 2);
      expect(chunks.map((c) => c.message?.content ?? '').join(), 'ok');
    });

    test('a 400 is surfaced immediately', () async {
      final client = _ScriptedClient([
        (400, '{"type":"error","error":{"type":"invalid_request_error"}}'),
      ]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1);
    });

    test('a failure after output has been emitted is never retried', () async {
      // Re-running would deliver the turn's opening twice.
      final client = _ScriptedClient([
        (200, _partialThenOverloaded),
        (200, _okBody),
      ]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1, reason: 'output already reached the caller');
    });

    test('the attempts are bounded by the config', () async {
      final client = _ScriptedClient([(200, _overloaded)]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 3, reason: '1 initial + 2 retries');
    });

    test('a healthy turn is sent exactly once', () async {
      final client = _ScriptedClient([(200, _okBody)]);

      await _run(client);

      expect(client.attempts, 1);
    });
  });
}
