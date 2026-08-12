/// Coverage for retry defaults, stream deadlines, embedding batching, and
/// capability reporting.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

String _sse(List<Map<String, dynamic>> frames) =>
    '${frames.map((f) => 'data: ${json.encode(f)}\n\n').join()}data: [DONE]\n\n';

Map<String, dynamic> _contentFrame(String text) => {
  'id': 'chatcmpl-1',
  'object': 'chat.completion.chunk',
  'created': 1,
  'model': 'test-model',
  'choices': [
    {
      'index': 0,
      'delta': {'content': text},
      'finish_reason': null,
    },
  ],
};

/// Fails a configurable number of times before succeeding.
class _FlakyClient extends http.BaseClient {
  _FlakyClient({required this.failures});
  int failures;
  static const int statusCode = 503;
  int attempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    attempts++;
    if (failures > 0) {
      failures--;
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"loading model weights"}')),
        statusCode,
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(_sse([_contentFrame('ok')]))),
      200,
    );
  }
}

/// Records every embedding request body it receives.
class _EmbeddingClient extends http.BaseClient {
  final List<List<String>> batches = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final body = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    final input = (body['input'] as List).cast<String>();
    batches.add(input);
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          json.encode({
            'object': 'list',
            'data': [
              for (var i = 0; i < input.length; i++)
                {
                  'object': 'embedding',
                  'index': i,
                  'embedding': [i.toDouble()],
                },
            ],
            'model': 'embed',
            'usage': {'prompt_tokens': 1, 'total_tokens': 1},
          }),
        ),
      ),
      200,
    );
  }
}

void main() {
  group('retry defaults', () {
    test('retries a 503 without any explicit RetryConfig', () async {
      // A freshly started vLLM answers 503 while loading weights. Defaulting
      // to no retries made that the common first-run failure.
      final client = _FlakyClient(failures: 2);
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      final chunks = await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .toList();

      expect(client.attempts, 3);
      expect(chunks, isNotEmpty);
    });

    test('opting out with maxAttempts: 0 still sends once', () async {
      final client = _FlakyClient(failures: 0);
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
        retryConfig: const RetryConfig(maxAttempts: 0),
      );

      await repo
          .streamChat(
            'test-model',
            messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
          )
          .toList();

      expect(client.attempts, 1);
    });

    test('exposes the default policy', () {
      expect(VLLMChatRepository.defaultRetryConfig.maxAttempts, 3);
      expect(
        VLLMChatRepository.defaultRetryConfig.retryableStatusCodes,
        contains(503),
      );
    });
  });

  group('capabilities', () {
    test('reports backend capabilities when none are configured', () {
      final repo = VLLMChatRepository(baseUrl: 'http://localhost:8000');
      expect(
        repo.capabilitiesForModel('any-model'),
        VLLMChatRepository.backendCapabilities,
      );
    });

    test('a configured value wins, so probes can correct the defaults', () {
      // Tool calling needs server flags and embeddings need an embedding
      // model, so the backend-level answer is not the deployment's answer.
      const probed = LLMCapabilities(
        streaming: true,
        structuredOutput: true,
        tools: false,
        embeddings: false,
      );
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        capabilities: probed,
      );

      final reported = repo.capabilitiesForModel('Qwen/Qwen3-0.6B');
      expect(reported.tools, isFalse);
      expect(reported.embeddings, isFalse);
      expect(reported.structuredOutput, isTrue);
    });
  });

  group('batchEmbed', () {
    test('splits large inputs and preserves order', () async {
      final client = _EmbeddingClient();
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      final inputs = List.generate(70, (i) => 'text $i');
      final result = await repo.batchEmbed(model: 'embed', messages: inputs);

      // 70 inputs at the default batch size of 32 → 32 / 32 / 6.
      expect(client.batches.map((b) => b.length), [32, 32, 6]);
      expect(result, hasLength(70));
      expect(
        client.batches.expand((b) => b).toList(),
        inputs,
        reason: 'inputs must be embedded in their original order',
      );
    });

    test('honors an explicit batch_size', () async {
      final client = _EmbeddingClient();
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo.batchEmbed(
        model: 'embed',
        messages: List.generate(10, (i) => 'text $i'),
        options: const {'batch_size': 4},
      );

      expect(client.batches.map((b) => b.length), [4, 4, 2]);
      // batch_size is a client-side concern and must not reach the server.
      expect(client.batches, isNotEmpty);
    });

    test('batch_size 0 sends everything in one request', () async {
      final client = _EmbeddingClient();
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo.batchEmbed(
        model: 'embed',
        messages: List.generate(50, (i) => 'text $i'),
        options: const {'batch_size': 0},
      );

      expect(client.batches, hasLength(1));
      expect(client.batches.single, hasLength(50));
    });

    test('a small input list is a single request', () async {
      final client = _EmbeddingClient();
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo.batchEmbed(model: 'embed', messages: ['a', 'b']);
      expect(client.batches, hasLength(1));
    });
  });

  systemMessageTests();

  group('stream deadline', () {
    test('a slow but alive stream trips the total timeout', () async {
      // readTimeout only measures the gap between chunks, so a stream that
      // keeps trickling never trips it. totalTimeout bounds the whole thing.
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: _TricklingClient(),
        timeoutConfig: const TimeoutConfig(
          readTimeout: Duration(seconds: 30),
          totalTimeout: Duration(milliseconds: 300),
        ),
      );

      expect(
        () => repo
            .streamChat(
              'test-model',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

/// Emits a chunk every 50ms, forever — never idle long enough for
/// `readTimeout` to fire, so only a total deadline can end it.
class _TricklingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();

    Stream<List<int>> trickle() async* {
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        yield utf8.encode('data: ${json.encode(_contentFrame('.'))}\n\n');
      }
    }

    return http.StreamedResponse(trickle(), 200);
  }
}

/// Captures the serialized messages array.
class _MessageCapturingClient extends http.BaseClient {
  List<Map<String, dynamic>> messages = const [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final body = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    return http.StreamedResponse(
      Stream.value(utf8.encode(_sse([_contentFrame('ok')]))),
      200,
    );
  }
}

void systemMessageTests() {
  group('system messages', () {
    test('merges adjacent system messages into one', () async {
      // Qwen3-family templates accept exactly one system message and reject
      // the rest with "System message must be at the beginning" — even when
      // every system message is at the beginning.
      final client = _MessageCapturingClient();
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [
              LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
              LLMMessage(role: LLMRole.system, content: 'Always be concise.'),
              LLMMessage(role: LLMRole.user, content: 'What is 2+2?'),
            ],
          )
          .toList();

      expect(client.messages, hasLength(2));
      expect(client.messages.first['role'], 'system');
      expect(
        client.messages.first['content'],
        'You are helpful.\n\nAlways be concise.',
      );
      expect(client.messages.last['role'], 'user');
    });

    test('leaves non-adjacent system messages in place', () async {
      // Moving these would change the conversation's meaning.
      final client = _MessageCapturingClient();
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [
              LLMMessage(role: LLMRole.system, content: 'A'),
              LLMMessage(role: LLMRole.user, content: 'hi'),
              LLMMessage(role: LLMRole.system, content: 'B'),
            ],
          )
          .toList();

      expect(client.messages.map((m) => m['role']), [
        'system',
        'user',
        'system',
      ]);
    });

    test('a single system message is untouched', () async {
      final client = _MessageCapturingClient();
      final repo = VLLMChatRepository(
        baseUrl: 'http://localhost:8000',
        httpClient: client,
      );

      await repo
          .streamChat(
            'test-model',
            messages: [
              LLMMessage(role: LLMRole.system, content: 'only one'),
              LLMMessage(role: LLMRole.user, content: 'hi'),
            ],
          )
          .toList();

      expect(client.messages, hasLength(2));
      expect(client.messages.first['content'], 'only one');
    });
  });
}
