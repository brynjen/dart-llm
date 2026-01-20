/// Comprehensive test suite for llm_chatgpt.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_chatgpt
/// dart test
/// ```
library;

import 'chatgpt_chat_repository_builder_test.dart' as builder;
import 'chatgpt_chat_repository_test.dart' as chatgpt_chat_repository;
import 'gpt_dto_test.dart' as dto;
import 'gpt_embedding_test.dart' as embedding;
import 'gpt_stream_decoder_test.dart' as stream_decoder;
import 'retry_test.dart' as retry;

void main() {
  chatgpt_chat_repository.main();
  retry.main();
  dto.main();
  stream_decoder.main();
  builder.main();
  embedding.main();
}
