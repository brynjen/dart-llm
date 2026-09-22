/// A provider can answer `200`, open the stream and only then report a failure
/// in-band. That error arrives after the send has returned, so the retry around
/// the send cannot see it — the same 503 it would have retried three times went
/// unretried, and the turn simply failed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

String _errorFrame(Object code) =>
    'data: ${json.encode({
      'error': {'message': 'high demand', 'code': code},
    })}\n\n';

String _contentFrame(String text, {String? finish}) =>
    'data: ${json.encode({
      'id': 'c1',
      'created': 1700000000,
      'model': 'm',
      'choices': [
        {
          'index': 0,
          'delta': {'role': 'assistant', 'content': text},
          'finish_reason': finish,
        },
      ],
    })}\n\n';

const _ok = 'data: [DONE]\n\n';

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
    VLLMChatRepository(
          httpClient: client,
          // No backoff, so the test does not wait on real delays.
          retryConfig: const RetryConfig(
            maxAttempts: 3,
            initialDelay: Duration.zero,
          ),
        )
        .streamChat(
          'm',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        )
        .toList();

void main() {
  group('in-band errors are retried while nothing has been emitted', () {
    test(
      'a retryable error before any output is retried and recovers',
      () async {
        final client = _ScriptedClient([
          _errorFrame(503),
          _contentFrame('ok', finish: 'stop') + _ok,
        ]);

        final chunks = await _run(client);

        expect(client.attempts, 2, reason: 'the 503 turn should be re-issued');
        expect(chunks.map((c) => c.message?.content ?? '').join(), 'ok');
      },
    );

    test('it gives up after the configured attempts', () async {
      final client = _ScriptedClient([_errorFrame(503)]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      // 1 initial + 3 retries.
      expect(client.attempts, 4);
    });

    test('a non-retryable in-band error is not retried', () async {
      final client = _ScriptedClient([_errorFrame(400)]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1);
    });

    test('an error after output has been emitted is never retried', () async {
      // Re-running would deliver the turn's opening twice, so however
      // retryable the error looks it has to surface.
      final client = _ScriptedClient([
        _contentFrame('partial') + _errorFrame(503),
        _contentFrame('ok', finish: 'stop') + _ok,
      ]);

      await expectLater(_run(client), throwsA(isA<LLMApiException>()));
      expect(client.attempts, 1, reason: 'output already reached the caller');
    });

    test('the priming delta does not count as output', () async {
      // vLLM opens with an empty content delta announcing the role. It is
      // suppressed, the caller has seen nothing, so a retry is still safe.
      final client = _ScriptedClient([
        _contentFrame('') + _errorFrame(503),
        _contentFrame('ok', finish: 'stop') + _ok,
      ]);

      final chunks = await _run(client);

      expect(client.attempts, 2);
      expect(chunks.map((c) => c.message?.content ?? '').join(), 'ok');
    });

    test('a healthy turn is sent exactly once', () async {
      final client = _ScriptedClient([
        _contentFrame('ok', finish: 'stop') + _ok,
      ]);

      await _run(client);

      expect(client.attempts, 1);
    });
  });

  group('the two retry budgets do not compound', () {
    test('an HTTP-level 503 is retried by the send only', () async {
      // The send raises a retryable status itself, so `executeWithRetry`
      // around it owns that failure. If `retryingStream` also retried it the
      // attempts would multiply — 4 becomes 16 against a server that is simply
      // down.
      final client = _StatusClient(503);

      await expectLater(
        VLLMChatRepository(
              httpClient: client,
              retryConfig: const RetryConfig(
                maxAttempts: 3,
                initialDelay: Duration.zero,
              ),
            )
            .streamChat(
              'm',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(isA<LLMApiException>()),
      );

      expect(client.attempts, 4, reason: '1 initial + 3 retries, not 16');
    });

    test('a transport failure is retried by the send only', () async {
      final client = _ThrowingClient();

      await expectLater(
        VLLMChatRepository(
              httpClient: client,
              retryConfig: const RetryConfig(
                maxAttempts: 2,
                initialDelay: Duration.zero,
              ),
            )
            .streamChat(
              'm',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(anything),
      );

      expect(client.attempts, 3, reason: '1 initial + 2 retries, not 9');
    });
  });

  group('a read timeout is not multiplied', () {
    test(
      'a stream that goes silent fails once, not maxAttempts times',
      () async {
        // The read timeout has already waited for TimeoutConfig.readTimeout
        // before it fires. Retrying it would turn a slow failure into what reads
        // as a hang, so it is excluded from the stream retry.
        final client = _SilentBodyClient();

        await expectLater(
          VLLMChatRepository(
                httpClient: client,
                timeoutConfig: const TimeoutConfig(
                  readTimeout: Duration(milliseconds: 150),
                ),
                retryConfig: const RetryConfig(
                  maxAttempts: 3,
                  initialDelay: Duration.zero,
                ),
              )
              .streamChat(
                'm',
                messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              )
              .toList(),
          throwsA(isA<TimeoutException>()),
        );

        expect(
          client.attempts,
          1,
          reason: 'a read timeout must not be re-issued',
        );
      },
    );
  });
}

/// Always answers with the same non-2xx status.
class _StatusClient extends http.BaseClient {
  _StatusClient(this.status);

  final int status;
  int attempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    attempts++;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"error":"unavailable"}')),
      status,
    );
  }
}

/// Fails at the transport layer, before any response exists.
class _ThrowingClient extends http.BaseClient {
  int attempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    attempts++;
    throw http.ClientException('connection closed', request.url);
  }
}

/// Opens a stream and then never sends anything.
class _SilentBodyClient extends http.BaseClient {
  int attempts = 0;
  final _body = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    attempts++;
    return http.StreamedResponse(
      _body.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}
