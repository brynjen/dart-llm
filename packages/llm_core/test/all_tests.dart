/// Comprehensive test suite for llm_core.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_core
/// dart test
/// ```
library;

import 'chat_response_test.dart' as chat_response;
import 'llm_metrics_test.dart' as metrics;
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
}
