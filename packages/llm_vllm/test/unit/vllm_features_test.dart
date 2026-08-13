/// Coverage for the constructor features that used to be accepted but never
/// exercised by any test: response caching, metrics recording, rate-limiter
/// wiring, and the hardened `embed` option handling.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

void main() {
  group('response cache', () {
    test('second identical chatResponse is served from cache', () async {
      final client = _ChatClient();
      final cache = MemoryResponseCache();
      final repo = VLLMChatRepository(httpClient: client, responseCache: cache);

      const options = LLMChatOptions(useCache: true);
      final messages = [LLMMessage(role: LLMRole.user, content: 'hi')];

      final first = await repo.chatResponse(
        'test-model',
        messages: messages,
        options: options,
      );
      final second = await repo.chatResponse(
        'test-model',
        messages: messages,
        options: options,
      );

      expect(client.sendCount, 1);
      expect(second.content, first.content);
      expect(cache.stats.hits, 1);
    });

    test('cache is bypassed when useCache is false', () async {
      final client = _ChatClient();
      final repo = VLLMChatRepository(
        httpClient: client,
        responseCache: MemoryResponseCache(),
      );

      final messages = [LLMMessage(role: LLMRole.user, content: 'hi')];
      await repo.chatResponse('test-model', messages: messages);
      await repo.chatResponse('test-model', messages: messages);

      expect(client.sendCount, 2);
    });
  });

  group('metrics', () {
    test('successful chatResponse records request/latency/tokens', () async {
      final metrics = DefaultLLMMetrics();
      final repo = VLLMChatRepository(
        httpClient: _ChatClient(),
        metrics: metrics,
      );

      await repo.chatResponse(
        'test-model',
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: const LLMChatOptions(recordMetrics: true),
      );

      final recorded = metrics.getMetrics();
      expect(recorded['test-model.total_requests'], 1);
      expect(recorded['test-model.successful_requests'], 1);
      expect(recorded['test-model.total_generated_tokens'], 1);
    });

    test('failed chatResponse records the error', () async {
      final metrics = DefaultLLMMetrics();
      final repo = VLLMChatRepository(
        httpClient: _StatusClient(500),
        metrics: metrics,
        retryConfig: const RetryConfig(maxAttempts: 0),
      );

      await expectLater(
        repo.chatResponse(
          'test-model',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          options: const LLMChatOptions(recordMetrics: true),
        ),
        throwsA(isA<LLMApiException>()),
      );

      final recorded = metrics.getMetrics();
      expect(recorded['test-model.failed_requests'], 1);
    });
  });

  group('rate limiter', () {
    test('requests pass through an enabled rate limiter', () async {
      final client = _ChatClient();
      final repo = VLLMChatRepository(
        httpClient: client,
        rateLimiter: const RateLimiter(
          maxRequests: 100,
          windowDuration: Duration(seconds: 1),
        ),
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .toList();
      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .toList();

      expect(client.sendCount, 2);
      repo.close();
    });
  });

  group('embed option handling', () {
    test('rejects an empty input list', () async {
      final repo = VLLMChatRepository(httpClient: _EmbedClient());
      await expectLater(
        repo.embed(model: 'embed-model', messages: []),
        throwsArgumentError,
      );
    });

    test('rejects unknown options with a suggestion', () async {
      // Same rationale as chat: the embeddings endpoint silently drops
      // unknown fields, so a typo must fail loudly client-side.
      final repo = VLLMChatRepository(httpClient: _EmbedClient());
      await expectLater(
        repo.embed(
          model: 'embed-model',
          messages: ['hi'],
          options: {'dimentions': 128},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('dimensions'),
          ),
        ),
      );
    });

    test('rejects chat-only sampling params for embeddings', () async {
      final repo = VLLMChatRepository(httpClient: _EmbedClient());
      await expectLater(
        repo.embed(
          model: 'embed-model',
          messages: ['hi'],
          options: {'temperature': 0.2},
        ),
        throwsArgumentError,
      );
    });

    test('normalizes aliases onto the wire', () async {
      final client = _EmbedClient();
      final repo = VLLMChatRepository(httpClient: client);

      await repo.embed(
        model: 'embed-model',
        messages: ['hi'],
        options: {'encodingFormat': 'float', 'dimensions': 128},
      );

      final body = client.bodies.single;
      expect(body['encoding_format'], 'float');
      expect(body['dimensions'], 128);
      expect(body.containsKey('encodingFormat'), isFalse);
    });

    test('client-side keys are never sent', () async {
      final client = _EmbedClient();
      final repo = VLLMChatRepository(httpClient: client);

      await repo.embed(
        model: 'embed-model',
        messages: ['hi'],
        options: {'batch_size': 8, 'timeout': const Duration(seconds: 5)},
      );

      final body = client.bodies.single;
      expect(body.containsKey('batch_size'), isFalse);
      expect(body.containsKey('timeout'), isFalse);
    });

    test('rejects a non-Duration timeout', () async {
      final repo = VLLMChatRepository(httpClient: _EmbedClient());
      await expectLater(
        repo.embed(
          model: 'embed-model',
          messages: ['hi'],
          options: {'timeout': 5000},
        ),
        throwsArgumentError,
      );
    });

    test('reserved keys are rejected', () async {
      final repo = VLLMChatRepository(httpClient: _EmbedClient());
      await expectLater(
        repo.embed(
          model: 'embed-model',
          messages: ['hi'],
          options: {'input': 'sneaky'},
        ),
        throwsArgumentError,
      );
    });
  });

  group('malformed 200 responses', () {
    test('embed translates a bodyless 200 into LLMApiException', () async {
      final repo = VLLMChatRepository(
        httpClient: _StatusClient(200, body: '{"object":"list"}'),
      );

      await expectLater(
        repo.embed(model: 'embed-model', messages: ['hi']),
        throwsA(
          isA<LLMApiException>().having(
            (e) => e.message,
            'message',
            contains('Malformed vLLM embeddings response'),
          ),
        ),
      );
    });

    test('embed translates a non-JSON 200 into LLMApiException', () async {
      final repo = VLLMChatRepository(
        httpClient: _StatusClient(200, body: '<html>proxy page</html>'),
      );

      await expectLater(
        repo.embed(model: 'embed-model', messages: ['hi']),
        throwsA(isA<LLMApiException>()),
      );
    });

    test('models() translates a malformed body into LLMApiException', () async {
      final repo = VLLMRepository(httpClient: _StatusClient(200, body: '[]'));

      await expectLater(
        repo.models(),
        throwsA(
          isA<LLMApiException>().having(
            (e) => e.message,
            'message',
            contains('Malformed vLLM models response'),
          ),
        ),
      );
    });
  });
}

/// Streams one canned chat completion per request.
class _ChatClient extends http.BaseClient {
  int sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount += 1;
    final sse = StringBuffer()
      ..writeln(
        'data: ${json.encode({
          'id': 'chatcmpl-test',
          'created': 1700000000,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': 'ok'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 3, 'completion_tokens': 1, 'total_tokens': 4},
        })}',
      )
      ..writeln()
      ..writeln('data: [DONE]');
    return http.StreamedResponse(
      Stream.value(utf8.encode(sse.toString())),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

/// Answers every request with a fixed status and body.
class _StatusClient extends http.BaseClient {
  _StatusClient(this.statusCode, {this.body = ''});

  final int statusCode;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(utf8.encode(body)), statusCode);
  }
}

/// Records embedding request bodies and answers with one vector per input.
class _EmbedClient extends http.BaseClient {
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final body = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    bodies.add(body);
    final input = (body['input'] as List).cast<String>();
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          json.encode({
            'object': 'list',
            'model': 'embed-model',
            'data': [
              for (var i = 0; i < input.length; i++)
                {
                  'object': 'embedding',
                  'index': i,
                  'embedding': [i.toDouble()],
                },
            ],
            'usage': {'prompt_tokens': 1, 'total_tokens': 1},
          }),
        ),
      ),
      200,
    );
  }
}
