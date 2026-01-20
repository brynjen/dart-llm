/// Comprehensive test suite for llm_ollama.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_ollama
/// dart test
/// ```
library;

import 'ollama_chat_repository_builder_test.dart' as builder;
import 'ollama_chat_repository_test.dart' as ollama_chat_repository;
import 'ollama_dto_test.dart' as dto;
import 'ollama_embedding_test.dart' as embedding;
import 'retry_test.dart' as retry;

void main() {
  ollama_chat_repository.main();
  retry.main();
  dto.main();
  builder.main();
  embedding.main();
}
