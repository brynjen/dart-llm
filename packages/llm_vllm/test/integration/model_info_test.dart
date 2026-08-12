/// Integration tests for vLLM model listing.
library;

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('VLLM Integration Tests - Model Information', () {
    late VLLMRepository vllmRepo;

    setUp(() {
      vllmRepo = VLLMRepository(baseUrl: baseUrl, apiKey: apiKey);
    });

    test(
      'list models',
      () async {
        final models = await vllmRepo.models().timeout(
          const Duration(seconds: 30),
        );

        expect(models, isNotEmpty);
        expect(models.map((m) => m.id), contains(chatModel));
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
