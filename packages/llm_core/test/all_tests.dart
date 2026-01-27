/// Comprehensive test suite for llm_core.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_core
/// dart test
/// ```
///
/// Run only unit tests:
/// ```bash
/// dart test test/unit
/// ```
library;

import 'unit/chat_response_test.dart' as chat_response;
import 'unit/exceptions_test.dart' as exceptions;
import 'unit/interface_consistency_test.dart' as interface_consistency;
import 'unit/llm_chunk_test.dart' as llm_chunk;
import 'unit/llm_embedding_test.dart' as llm_embedding;
import 'unit/llm_message_test.dart' as llm_message;
import 'unit/llm_metrics_test.dart' as metrics;
import 'unit/llm_response_test.dart' as llm_response;
import 'unit/llm_tool_call_test.dart' as llm_tool_call;
import 'unit/llm_tool_param_test.dart' as llm_tool_param;
import 'unit/llm_tool_test.dart' as llm_tool;
import 'unit/retry_config_test.dart' as retry_config;
import 'unit/stream_chat_options_test.dart' as stream_chat_options;
import 'unit/timeout_config_test.dart' as timeout_config;
import 'unit/validation_test.dart' as validation;
import 'unit/validation_comprehensive_test.dart' as validation_comprehensive;
import 'unit/retry_util_test.dart' as retry_util;
import 'unit/mock_llm_chat_repository_test.dart' as mock_repo_test;

void main() {
  validation.main();
  validation_comprehensive.main();
  retry_config.main();
  retry_util.main();
  timeout_config.main();
  stream_chat_options.main();
  metrics.main();
  chat_response.main();
  llm_message.main();
  llm_chunk.main();
  llm_response.main();
  llm_tool_param.main();
  llm_tool.main();
  llm_tool_call.main();
  exceptions.main();
  llm_embedding.main();
  interface_consistency.main();
  mock_repo_test.main();
}
