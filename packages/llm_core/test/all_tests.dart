/// Comprehensive test suite for llm_core.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_core
/// dart test
/// ```
library;

import 'chat_response_test.dart' as chat_response;
import 'exceptions_test.dart' as exceptions;
import 'llm_chunk_test.dart' as llm_chunk;
import 'llm_embedding_test.dart' as llm_embedding;
import 'llm_message_test.dart' as llm_message;
import 'llm_metrics_test.dart' as metrics;
import 'llm_response_test.dart' as llm_response;
import 'llm_tool_call_test.dart' as llm_tool_call;
import 'llm_tool_param_test.dart' as llm_tool_param;
import 'llm_tool_test.dart' as llm_tool;
import 'retry_config_test.dart' as retry_config;
import 'stream_chat_options_test.dart' as stream_chat_options;
import 'timeout_config_test.dart' as timeout_config;
import 'validation_test.dart' as validation;

void main() {
  validation.main();
  retry_config.main();
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
}
