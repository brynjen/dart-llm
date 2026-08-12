/// Integration tests for concurrent request handling.
///
/// vLLM batches concurrent requests continuously, so a single repository is
/// expected to sustain many simultaneous streams over one HTTP client. These
/// tests exercise that path — the server's own concurrency is not in question,
/// the library's sharing of a client and per-stream state is.
///
/// Part of the comprehensive VLLM integration test suite.
library;

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('VLLM Integration Tests - Concurrency', () {
    late VLLMChatRepository repo;

    setUp(() {
      repo = createRepository();
    });

    tearDown(() {
      repo.close();
    });

    test(
      'sustains 16 concurrent streams through one repository',
      () async {
        const concurrency = 16;

        final futures = List.generate(concurrency, (i) async {
          final chunks = await collectStreamWithTimeout(
            repo.streamChat(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content: 'Write one short sentence about the number $i.',
                ),
              ],
              options: const LLMChatOptions(think: false, maxOutputTokens: 120),
            ),
            const Duration(seconds: 120),
          );
          return (index: i, content: extractContent(chunks), chunks: chunks);
        });

        final results = await Future.wait(futures);

        expect(results, hasLength(concurrency));
        for (final result in results) {
          expect(
            result.content.trim(),
            isNotEmpty,
            reason: 'stream ${result.index} produced no content',
          );
          expect(
            result.chunks.any((c) => c.done == true),
            isTrue,
            reason: 'stream ${result.index} never terminated',
          );
        }

        // Responses must not be cross-contaminated: each stream carries its own
        // accumulator state, so identical output across all of them would point
        // at shared mutable state in the converter.
        final distinct = results.map((r) => r.content.trim()).toSet();
        expect(
          distinct.length,
          greaterThan(1),
          reason:
              'all concurrent streams returned identical text, which '
              'suggests shared state between streams',
        );
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'concurrent streams each report their own usage',
      () async {
        final futures = List.generate(8, (i) async {
          final chunks = await collectStreamWithTimeout(
            repo.streamChat(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content: 'Repeat the word "token" exactly $i times.',
                ),
              ],
              options: const LLMChatOptions(think: false),
            ),
            const Duration(seconds: 120),
          );
          return chunks.where((c) => c.usage != null).toList();
        });

        final usageChunks = await Future.wait(futures);

        for (var i = 0; i < usageChunks.length; i++) {
          expect(
            usageChunks[i],
            isNotEmpty,
            reason:
                'stream $i reported no usage; stream_options.include_usage '
                'should yield a usage frame before [DONE]',
          );
          final usage = usageChunks[i].last.usage!;
          expect(usage.promptTokens, greaterThan(0));
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'base URL is accepted with or without the /v1 suffix',
      () async {
        // vLLM's own docs print the base URL as `http://host:port/v1`, so both
        // spellings reach the library in practice. They must hit the same
        // endpoint rather than producing /v1/v1/... and a 404.
        final withSuffix = createRepository(
          customBaseUrl: '${normalizeVllmBaseUrl(baseUrl)}/v1',
        );
        addTearDown(withSuffix.close);

        final chunks = await collectStreamWithTimeout(
          withSuffix.streamChat(
            chatModel,
            messages: [LLMMessage(role: LLMRole.user, content: 'Say OK.')],
            options: const LLMChatOptions(think: false, maxOutputTokens: 16),
          ),
          const Duration(seconds: 60),
        );

        expect(extractContent(chunks).trim(), isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, tags: ['integration']);
}
