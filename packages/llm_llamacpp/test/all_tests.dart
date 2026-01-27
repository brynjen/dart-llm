/// Comprehensive integration test suite for llm_llamacpp.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_llamacpp
/// LD_LIBRARY_PATH=linux/libs dart test test/all_tests.dart
/// ```
///
/// Run only integration tests:
/// ```bash
/// dart test test/integration
/// ```
///
/// Run with specific model:
/// ```bash
/// LLAMA_TEST_MODEL=/path/to/model.gguf \
/// LLAMA_TEST_VISION_MODEL=/path/to/vision-model.gguf \
/// LLAMA_TEST_GPU_LAYERS=99 \
/// LD_LIBRARY_PATH=linux/libs dart test test/all_tests.dart
/// ```
///
/// Run specific test file:
/// ```bash
/// LD_LIBRARY_PATH=linux/libs dart test test/integration/model_loading_test.dart
/// ```
library;

import 'integration/model_loading_test.dart' as model_loading;
import 'integration/text_generation_test.dart' as text_generation;
import 'integration/vision_model_test.dart' as vision_model;
import 'integration/tool_use_test.dart' as tool_use;
import 'integration/embeddings_test.dart' as embeddings;
import 'integration/error_handling_test.dart' as error_handling;
import 'integration/edge_cases_test.dart' as edge_cases;
import 'integration/streaming_test.dart' as streaming;
import 'integration/chat_history_test.dart' as chat_history;

void main() {
  model_loading.main();
  text_generation.main();
  vision_model.main();
  tool_use.main();
  embeddings.main();
  error_handling.main();
  edge_cases.main();
  streaming.main();
  chat_history.main();
}
