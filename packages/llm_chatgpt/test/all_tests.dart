/// Comprehensive test suite for llm_chatgpt.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_chatgpt
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
/// OPENAI_API_KEY=your-key dart test test/integration
/// ```
library;

import 'unit/chatgpt_chat_repository_builder_test.dart' as builder;
import 'unit/chatgpt_chat_repository_test.dart' as chatgpt_chat_repository;
import 'unit/gpt_dto_test.dart' as dto;
import 'unit/gpt_embedding_test.dart' as embedding;
import 'unit/gpt_stream_decoder_test.dart' as stream_decoder;
import 'unit/retry_test.dart' as retry;

// Integration tests - will skip themselves if API key is not available
import 'integration/all_integration_tests.dart' as integration;

void main() {
  chatgpt_chat_repository.main();
  retry.main();
  dto.main();
  stream_decoder.main();
  builder.main();
  embedding.main();

  // Integration tests will skip themselves if API key is not available
  integration.main();
}
