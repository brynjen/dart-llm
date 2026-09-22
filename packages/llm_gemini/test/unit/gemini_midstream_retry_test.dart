/// Retryable failures on a streaming turn, by the two routes they arrive on.
///
/// A non-2xx is a *returned* response, not a thrown error, so the retry around
/// the send never saw it — `RetryConfig.retryableStatusCodes` did not apply to
/// streaming at all. Gemini also answers `200` and reports capacity failures
/// in-band, as an `error` event, which arrives after the send has returned.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_gemini/llm_gemini.dart';
import 'package:test/test.dart';

String _line(Map<String, dynamic> data) => 'data: ${json.encode(data)}\n';

final _okBody =
    _line({
      'event_type': 'interaction.created',
      'interaction': {
        'id': 'int_1',
        'model': 'gemini-3.5-flash-lite',
        'status': 'in_progress',
      },
    }) +
    _line({
      'event_type': 'step.delta',
      'index': 0,
      'delta': {'type': 'text', 'text': 'ok'},
    }) +
    _line({
      'event_type': 'interaction.completed',
      'interaction': {'id': 'int_1', 'status': 'completed'},
    });

/// Captured verbatim from the live free tier.
final _highDemand = _line({
  'error': {
    'message':
        'gemini-3.5-flash-lite is currently experiencing high demand, spikes '
        'in demand are usually temporary. Please try again later.',
    'code': 'service_unavailable',
  },
  'event_type': 'error',
});

final _partialThenHighDemand =
    _line({
      'event_type': 'interaction.created',
      'interaction': {
        'id': 'int_1',
        'model': 'gemini-3.5-flash-lite',
        'status': 'in_progress',
      },
    }) +
    _line({
      'event_type': 'step.delta',
      'index': 0,
      'delta': {'type': 'text', 'text': 'partial'},
    }) +
    _highDemand;

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
    GeminiChatRepository(
          apiKey: 'k',
          httpClient: client,
          retryConfig: const RetryConfig(
            maxAttempts: 2,
            initialDelay: Duration.zero,
          ),
        )
        .streamChat(
          'gemini-3.5-flash-lite',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        )
        .toList();

void main() {
  group('retryable failures on a streaming turn', () {
    test('a 503 response is retried and recovers', () async {
      // This is the failure seen live: Google answers 503 while the model is
      // over capacity. It used to fail on the first attempt.
      final client = _ScriptedClient([
        (503, '{"error":{"message":"high demand"}}'),
        (200, _okBody),
      ]);

      final chunks = await _run(client);

      expect(client.attempts, 2, reason: 'a retryable status must be retried');
      expect(chunks.map((c) => c.message?.content ?? '').join(), 'ok');
    });

    test(
      'an in-band service_unavailable before any output is retried',
      () async {
        // `service_unavailable` is the spelling Google actually sends; only the
        // gRPC `UNAVAILABLE` was mapped, so this carried no status and could
        // never be classified as retryable.
        final client = _ScriptedClient([(200, _highDemand), (200, _okBody)]);

        final chunks = await _run(client);

        expect(client.attempts, 2);
        expect(chunks.map((c) => c.message?.content ?? '').join(), 'ok');
      },
    );

    test('a 400 is surfaced immediately', () async {
      final client = _ScriptedClient([
        (400, '{"error":{"message":"bad request"}}'),
      ]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1);
    });

    test('a failure after output has been emitted is never retried', () async {
      final client = _ScriptedClient([
        (200, _partialThenHighDemand),
        (200, _okBody),
      ]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1, reason: 'output already reached the caller');
    });

    test('the attempts are bounded by the config', () async {
      final client = _ScriptedClient([(200, _highDemand)]);

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
