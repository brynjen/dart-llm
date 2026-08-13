import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:llm_vllm/llm_vllm.dart';
import 'package:llm_vllm/src/pool/semaphore.dart';
import 'package:test/test.dart';

void main() {
  group('Semaphore', () {
    test('immediately grants permits up to maxCount', () async {
      final s = Semaphore(3);
      expect(s.available, 3);
      await s.acquire();
      expect(s.available, 2);
      await s.acquire();
      expect(s.available, 1);
      await s.acquire();
      expect(s.available, 0);
    });

    test('blocks when at capacity and releases on release()', () async {
      final s = Semaphore(1);
      await s.acquire();
      expect(s.available, 0);

      var released = false;
      final waiter = s.acquire().then((_) => released = true);

      await Future<void>.delayed(Duration.zero);
      expect(released, false);
      expect(s.waiting, 1);

      s.release();
      await waiter;
      expect(released, true);
      expect(s.waiting, 0);
    });

    test('acquireWithTimeout throws VLLMQueueTimeoutException', () async {
      final s = Semaphore(1);
      await s.acquire();

      expect(
        () => s.acquireWithTimeout(const Duration(milliseconds: 10)),
        throwsA(isA<VLLMQueueTimeoutException>()),
      );
    });
  });

  group('VLLMModelConfig.matches', () {
    test('exact match', () {
      const c = VLLMModelConfig(pattern: 'Qwen/Qwen3-4B');
      expect(c.matches('Qwen/Qwen3-4B'), true);
      expect(c.matches('Qwen/Qwen3-8B'), false);
    });

    test('wildcard match', () {
      const c = VLLMModelConfig(pattern: 'Qwen/*');
      expect(c.matches('Qwen/Qwen3-4B'), true);
      expect(c.matches('meta-llama/Llama-3.2-3B'), false);
    });
  });

  group('VLLMInstanceConfig', () {
    test('acceptsModel empty exclusiveModels accepts all', () {
      const c = VLLMInstanceConfig(baseUrl: 'http://x');
      expect(c.acceptsModel('anything'), true);
    });

    test('acceptsModel filters exclusive models', () {
      const c = VLLMInstanceConfig(
        baseUrl: 'http://x',
        exclusiveModels: ['large-model'],
      );
      expect(c.acceptsModel('large-model'), true);
      expect(c.acceptsModel('small-model'), false);
    });

    test('prefersModel returns true only for preferredModels', () {
      const c = VLLMInstanceConfig(
        baseUrl: 'http://x',
        preferredModels: ['small-model'],
      );
      expect(c.prefersModel('small-model'), true);
      expect(c.prefersModel('large-model'), false);
    });
  });

  group('VLLMPool construction', () {
    test('creates via constructor', () {
      final pool = VLLMPool(
        instances: [const VLLMInstanceConfig(baseUrl: 'http://localhost')],
      );
      final stats = pool.stats();
      expect(stats.instances.length, 1);
      expect(stats.instances.first.baseUrl, 'http://localhost');
      expect(stats.instances.first.maxConcurrent, 3);
      pool.dispose();
    });

    test('creates via builder', () {
      final pool = VLLMPool.builder()
          .addInstance(
            const VLLMInstanceConfig(
              baseUrl: 'http://gpu1:8000',
              apiKey: 'a',
              maxConcurrent: 4,
            ),
          )
          .addInstance(
            const VLLMInstanceConfig(
              baseUrl: 'http://gpu2:8000',
              maxConcurrent: 1,
            ),
          )
          .addModelConfig(
            const VLLMModelConfig(
              pattern: 'large-model',
              maxConcurrent: 1,
              exclusive: true,
            ),
          )
          .queueTimeout(const Duration(seconds: 10))
          .maxQueueDepth(100)
          .build();

      final stats = pool.stats();
      expect(stats.instances.length, 2);
      expect(stats.healthyInstances, 2);
      expect(pool.queueTimeout, const Duration(seconds: 10));
      expect(pool.maxQueueDepth, 100);
      expect(pool.modelConfigs.length, 1);
      pool.dispose();
    });

    test('instances() replaces previous entries', () {
      final pool = VLLMPoolBuilder()
          .addInstance(const VLLMInstanceConfig(baseUrl: 'http://old'))
          .instances([const VLLMInstanceConfig(baseUrl: 'http://new')])
          .build();

      expect(pool.stats().instances.length, 1);
      expect(pool.stats().instances.first.baseUrl, 'http://new');
      pool.dispose();
    });
  });

  group('VLLMPool routing', () {
    test(
      'throws VLLMNoEligibleInstanceException when no instance accepts model',
      () {
        final pool = VLLMPool(
          instances: [
            const VLLMInstanceConfig(
              baseUrl: 'http://gpu1:8000',
              exclusiveModels: ['large-model'],
            ),
          ],
        );

        expect(
          () => pool
              .streamChat(
                'small-model',
                messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              )
              .toList(),
          throwsA(isA<VLLMNoEligibleInstanceException>()),
        );
        pool.dispose();
      },
    );

    test('throws VLLMQueueFullException when maxQueueDepth reached', () {
      final pool = VLLMPool(
        instances: [
          const VLLMInstanceConfig(
            baseUrl: 'http://gpu1:8000',
            maxConcurrent: 1,
          ),
        ],
        maxQueueDepth: 0,
      );

      expect(
        () => pool
            .streamChat(
              'small-model',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(isA<VLLMQueueFullException>()),
      );
      pool.dispose();
    });

    test('routes embed to preferEmbedding instances first', () async {
      final chatClient = _RecordingClient();
      final embedClient = _RecordingClient();
      final pool = VLLMPool(
        instances: [
          VLLMInstanceConfig(
            baseUrl: 'http://chat:8000',
            httpClient: chatClient,
          ),
          VLLMInstanceConfig(
            baseUrl: 'http://embed:8001',
            preferEmbedding: true,
            httpClient: embedClient,
          ),
        ],
      );

      await pool.embed(model: 'embed-model', messages: ['hi']);

      expect(embedClient.sendCount, 1);
      expect(chatClient.sendCount, 0);
      pool.dispose();
    });

    test('batchEmbed batches through the instance repository', () async {
      // Regression: batchEmbed used to delegate to embed(), sending the
      // whole list as one request and silently losing batching.
      final embedClient = _RecordingClient();
      final pool = VLLMPool(
        instances: [
          VLLMInstanceConfig(
            baseUrl: 'http://embed:8001',
            httpClient: embedClient,
          ),
        ],
      );

      final result = await pool.batchEmbed(
        model: 'embed-model',
        messages: ['a', 'b', 'c'],
        options: {'batch_size': 1},
      );

      expect(embedClient.sendCount, 3);
      expect(result, hasLength(3));
      pool.dispose();
    });
  });

  group('VLLMPool capabilities', () {
    test('OR-folds capabilities across eligible instances', () {
      final pool = VLLMPool(
        instances: [
          const VLLMInstanceConfig(
            baseUrl: 'http://chat:8000',
            exclusiveModels: ['chat-model'],
            capabilities: LLMCapabilities(tools: true, thinking: true),
          ),
          const VLLMInstanceConfig(
            baseUrl: 'http://embed:8001',
            exclusiveModels: ['embed-model'],
            capabilities: LLMCapabilities(embeddings: true),
          ),
        ],
      );

      final chat = pool.capabilitiesForModel('chat-model');
      expect(chat.tools, isTrue);
      expect(chat.thinking, isTrue);
      expect(chat.embeddings, isFalse);

      final embed = pool.capabilitiesForModel('embed-model');
      expect(embed.embeddings, isTrue);
      expect(embed.tools, isFalse);

      final none = pool.capabilitiesForModel('unknown-model');
      expect(none.streaming, isFalse);
      expect(none.tools, isFalse);
      expect(none.embeddings, isFalse);
      pool.dispose();
    });

    test('without explicit capabilities, backend defaults apply', () {
      // Wrapping repositories that support tools must not report tools:false
      // — the exact contradiction the override fixes.
      final pool = VLLMPool(
        instances: [const VLLMInstanceConfig(baseUrl: 'http://gpu1:8000')],
      );

      final caps = pool.capabilitiesForModel('any-model');
      expect(caps.tools, isTrue);
      expect(caps.streaming, isTrue);
      expect(caps.embeddings, isTrue);
      pool.dispose();
    });
  });

  group('VLLMPool queue depth under concurrency', () {
    test('a burst cannot all slip past the depth guard', () async {
      // The old guard sampled semaphore.waiting at check time, so a burst of
      // requests that all checked before any of them enqueued would all be
      // admitted. The counter is now maintained synchronously at admission.
      final gate = Completer<void>();
      final client = _RecordingClient(
        onChat: (_) async {
          await gate.future;
        },
      );
      final pool = VLLMPool(
        instances: [
          VLLMInstanceConfig(
            baseUrl: 'http://gpu1:8000',
            maxConcurrent: 1,
            httpClient: client,
          ),
        ],
        maxQueueDepth: 1,
      );

      final messages = [LLMMessage(role: LLMRole.user, content: 'hi')];

      // A occupies the slot; B fills the queue; C must be rejected.
      final a = pool.streamChat('m', messages: messages).toList();
      await _pumpEventQueue();
      final b = pool.streamChat('m', messages: messages).toList();
      await _pumpEventQueue();

      await expectLater(
        pool.streamChat('m', messages: messages).toList(),
        throwsA(isA<VLLMQueueFullException>()),
      );

      gate.complete();
      await a;
      await b;
      expect(client.sendCount, 2);
      pool.dispose();
    });
  });

  group('VLLMPool tool attempts', () {
    test('toolAttempts is forwarded to the pooled repository', () async {
      // A model that answers every request with another tool call: with
      // toolAttempts: 1 the loop must stop after the initial request plus one
      // follow-up, instead of running to the instance default of 90.
      final client = _RecordingClient(alwaysToolCall: true);
      final pool = VLLMPool(
        instances: [
          VLLMInstanceConfig(baseUrl: 'http://gpu1:8000', httpClient: client),
        ],
      );

      await expectLater(
        pool
            .streamChat(
              'm',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
              tools: [_EchoTool()],
              toolAttempts: 1,
            )
            .toList(),
        throwsA(isA<ToolLoopIncompleteException>()),
      );
      expect(client.sendCount, 2);
      pool.dispose();
    });
  });

  group('VLLMPool health checking', () {
    test('emits state changes and excludes unhealthy instances', () async {
      var healthy = false;
      final client = _RecordingClient(
        modelsStatusCode: () => healthy ? 200 : 500,
      );
      final pool = VLLMPool(
        instances: [
          VLLMInstanceConfig(baseUrl: 'http://gpu1:8000', httpClient: client),
        ],
        healthCheck: const HealthCheckConfig(
          interval: Duration(milliseconds: 20),
          timeout: Duration(seconds: 1),
        ),
      );

      final events = <VLLMInstanceStateChange>[];
      final sub = pool.onInstanceStateChange.listen(events.add);

      // Initial check fails -> healthy(true, the optimistic default) -> false.
      await _waitFor(() => events.isNotEmpty);
      expect(events.first.healthy, isFalse);
      expect(pool.stats().healthyInstances, 0);

      // Routing skips the unhealthy instance entirely.
      await expectLater(
        pool
            .streamChat(
              'm',
              messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            )
            .toList(),
        throwsA(isA<VLLMNoEligibleInstanceException>()),
      );

      // Server recovers -> transition back to healthy.
      healthy = true;
      await _waitFor(() => events.length >= 2);
      expect(events.last.healthy, isTrue);
      expect(pool.stats().healthyInstances, 1);

      await sub.cancel();
      pool.dispose();
    });
  });

  group('VLLMPool dispose', () {
    test('closes the state stream but not caller-supplied clients', () async {
      final client = _RecordingClient();
      final pool = VLLMPool(
        instances: [
          VLLMInstanceConfig(baseUrl: 'http://gpu1:8000', httpClient: client),
        ],
      );

      final done = pool.onInstanceStateChange.toList();
      pool.dispose();

      expect(await done, isEmpty, reason: 'stream must close on dispose');
      expect(
        client.closed,
        isFalse,
        reason: 'caller-supplied client is owned by the caller',
      );
    });
  });

  group('VLLMPool features', () {
    test('pool-level response cache short-circuits repeat requests', () async {
      final client = _RecordingClient();
      final cache = MemoryResponseCache();
      final pool = VLLMPool.builder()
          .addInstance(
            VLLMInstanceConfig(baseUrl: 'http://gpu1:8000', httpClient: client),
          )
          .responseCache(cache)
          .build();

      final messages = [LLMMessage(role: LLMRole.user, content: 'hi')];
      const options = LLMChatOptions(useCache: true);
      await pool.chatResponse('m', messages: messages, options: options);
      await pool.chatResponse('m', messages: messages, options: options);

      expect(client.sendCount, 1);
      expect(cache.stats.hits, 1);
      pool.dispose();
    });

    test('pool-level metrics record requests', () async {
      final metrics = DefaultLLMMetrics();
      final pool = VLLMPool.builder()
          .addInstance(
            VLLMInstanceConfig(
              baseUrl: 'http://gpu1:8000',
              httpClient: _RecordingClient(),
            ),
          )
          .metrics(metrics)
          .build();

      await pool.chatResponse(
        'm',
        messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: const LLMChatOptions(recordMetrics: true),
      );

      expect(metrics.getMetrics()['m.total_requests'], 1);
      pool.dispose();
    });
  });
}

Future<void> _pumpEventQueue() => Future<void>.delayed(Duration.zero);

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Fake vLLM server: answers `/chat/completions` with a canned SSE stream
/// (optionally a perpetual tool call), `/embeddings` with one vector per
/// input, and `/models` with a configurable status.
class _RecordingClient extends http.BaseClient {
  _RecordingClient({
    this.onChat,
    this.alwaysToolCall = false,
    this.modelsStatusCode,
  });

  /// Awaited before answering a chat request; lets tests hold a slot open.
  final Future<void> Function(http.BaseRequest request)? onChat;
  final bool alwaysToolCall;
  final int Function()? modelsStatusCode;

  int sendCount = 0;
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/models')) {
      final status = modelsStatusCode?.call() ?? 200;
      return http.StreamedResponse(
        Stream.value(utf8.encode(json.encode({'object': 'list', 'data': []}))),
        status,
      );
    }

    sendCount += 1;
    if (path.endsWith('/embeddings')) {
      final bytes = await request.finalize().toBytes();
      final body = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
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

    await onChat?.call(request);
    final frames = alwaysToolCall
        ? [
            {
              'id': 'chatcmpl-test',
              'created': 1700000000,
              'model': 'test-model',
              'choices': [
                {
                  'index': 0,
                  'delta': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'index': 0,
                        'type': 'function',
                        'function': {
                          'name': 'echo',
                          'arguments': '{"message":"hi"}',
                        },
                      },
                    ],
                  },
                  'finish_reason': null,
                },
              ],
            },
            {
              'id': 'chatcmpl-test',
              'created': 1700000000,
              'model': 'test-model',
              'choices': [
                {
                  'index': 0,
                  'delta': <String, dynamic>{},
                  'finish_reason': 'tool_calls',
                },
              ],
            },
          ]
        : [
            {
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
              'usage': {
                'prompt_tokens': 1,
                'completion_tokens': 1,
                'total_tokens': 2,
              },
            },
          ];
    final sse = StringBuffer();
    for (final frame in frames) {
      sse.writeln('data: ${json.encode(frame)}');
      sse.writeln();
    }
    sse.writeln('data: [DONE]');
    return http.StreamedResponse(
      Stream.value(utf8.encode(sse.toString())),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

class _EchoTool extends LLMTool {
  @override
  String get name => 'echo';

  @override
  String get description => 'Echoes back the message.';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'message',
      type: 'string',
      description: 'Message to echo.',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      args['message'];
}
