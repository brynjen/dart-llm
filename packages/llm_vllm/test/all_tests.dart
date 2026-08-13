/// Comprehensive test suite for llm_vllm.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_vllm
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

import 'unit/vllm_base_url_test.dart' as base_url;
import 'unit/vllm_params_test.dart' as params;
import 'unit/vllm_resilience_test.dart' as resilience;
import 'unit/vllm_chat_repository_builder_test.dart' as builder;
import 'unit/vllm_chat_repository_test.dart' as vllm_chat_repository;
import 'unit/vllm_dto_test.dart' as dto;
import 'unit/vllm_embedding_test.dart' as embedding;
import 'unit/vllm_error_handler_test.dart' as error_handler;
import 'unit/vllm_features_test.dart' as features;
import 'unit/vllm_pool_test.dart' as pool;
import 'unit/vllm_repository_test.dart' as repository;
import 'unit/vllm_request_shape_test.dart' as request_shape;
import 'unit/vllm_stream_converter_test.dart' as stream_converter;
import 'unit/retry_test.dart' as retry;

void main() {
  vllm_chat_repository.main();
  base_url.main();
  params.main();
  resilience.main();
  retry.main();
  dto.main();
  builder.main();
  embedding.main();
  error_handler.main();
  features.main();
  repository.main();
  request_shape.main();
  pool.main();
  stream_converter.main();
}
