/// Comprehensive integration test suite for llm_llamacpp.
///
/// Run all tests:
/// ```bash
/// cd packages/llm_llamacpp
/// LD_LIBRARY_PATH=linux/libs dart test test/all_tests.dart
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
/// LD_LIBRARY_PATH=linux/libs dart test test/model_loading_test.dart
/// ```
library;

import 'model_loading_test.dart' as model_loading;
import 'text_generation_test.dart' as text_generation;
import 'vision_model_test.dart' as vision_model;
import 'tool_use_test.dart' as tool_use;

void main() {
  model_loading.main();
  text_generation.main();
  vision_model.main();
  tool_use.main();
}
