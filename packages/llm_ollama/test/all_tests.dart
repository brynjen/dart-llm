/// Comprehensive test suite for llm_ollama.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_ollama
/// dart test
/// ```
///
/// Run only unit tests:
/// ```bash
/// dart test test/unit
/// ```
///
/// Run only integration tests:
/// ```bash
/// dart test test/integration
/// ```
library;

import 'unit/ollama_chat_repository_builder_test.dart' as builder;
import 'unit/ollama_chat_repository_test.dart' as ollama_chat_repository;
import 'unit/ollama_dto_test.dart' as dto;
import 'unit/ollama_embedding_test.dart' as embedding;
import 'unit/retry_test.dart' as retry;

void main() {
  ollama_chat_repository.main();
  retry.main();
  dto.main();
  builder.main();
  embedding.main();
}
