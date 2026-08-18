/// Integration test suite for llm_llamacpp. Unit tests live in `test/unit/`
/// and are picked up by a plain `dart test`.
///
/// These tests load a real GGUF model through the native library, so they need
/// both a model and a resolvable library. The build hook puts the library under
/// `.dart_tool/`, so point the loader at it with `LLM_LLAMACPP_LIB_DIR`:
///
/// ```bash
/// cd packages/llm_llamacpp
/// export LLM_LLAMACPP_LIB_DIR=$(dirname $(find .dart_tool/hooks_runner \
///   -name 'libllama.*' -o -name 'llama.dll' | head -1))
/// dart test test/all_tests.dart
/// ```
///
/// Run only unit tests (no model or native library needed):
/// ```bash
/// dart test test/unit
/// ```
///
/// Run with a specific model:
/// ```bash
/// LLAMA_TEST_MODEL=/path/to/model.gguf \
/// LLAMA_TEST_VISION_MODEL=/path/to/vision-model.gguf \
/// LLAMA_TEST_GPU_LAYERS=99 \
/// dart test test/all_tests.dart
/// ```
///
/// Run a specific test file:
/// ```bash
/// dart test test/integration/model_loading_test.dart
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
