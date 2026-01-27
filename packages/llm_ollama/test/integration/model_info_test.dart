/// Integration tests for Model Information
///
/// Part of the comprehensive Ollama integration test suite.
library;

import 'package:llm_ollama/llm_ollama.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Ollama Integration Tests - Model Information', () {
    late OllamaRepository ollamaRepo;

    setUp(() {
      ollamaRepo = OllamaRepository(baseUrl: baseUrl);
    });

    group('Model Information Tests', () {
      test(
        'list models',
        () async {
          final models = await ollamaRepo.models().timeout(
            const Duration(seconds: 30),
          );

          expect(models, isNotEmpty);
          expect(
            models.any((m) => m.name.contains(chatModel.split(':').first)),
            isTrue,
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'show model info',
        () async {
          final modelInfo = await ollamaRepo
              .showModel(chatModel)
              .timeout(const Duration(seconds: 30));

          expect(modelInfo.details, isNotNull);
          expect(modelInfo.modelfile, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'get Ollama version',
        () async {
          final version = await ollamaRepo.version().timeout(
            const Duration(seconds: 30),
          );

          expect(version.version, isNotEmpty);
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'check model capabilities',
        () async {
          final supportsVision = await ollamaRepo
              .supportsVision(chatModel)
              .timeout(const Duration(seconds: 30));

          expect(supportsVision, isA<bool>());
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(seconds: 30)),
      );
    });
  });
}
