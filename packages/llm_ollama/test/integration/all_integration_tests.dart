/// Comprehensive integration test suite for llm_ollama against a remote Ollama server.
///
/// This test suite verifies that the package can successfully communicate with
/// http://192.168.0.74:11434 using the gpt-oss:20b model for chat and
/// nomic-embed-text for embeddings.
///
/// The test suite is organized into categories for easier navigation:
/// - Basic Chat Tests - Streaming and non-streaming responses
/// - Chat History Tests - Multi-turn conversations, context preservation
/// - Tool Calling Tests - Single tools, multiple tools, tool chains
/// - Embedding Tests - Single embeddings, batch embeddings, similarity
/// - Thinking Mode Tests - Thinking content extraction
/// - Error Handling Tests - Invalid models, network errors
/// - Edge Case Tests - Empty messages, unicode, concurrent requests
/// - Model Information Tests - Model listing, version checking
/// - Streaming Behavior Tests - Chunk ordering, done flags
///
/// Run this test:
/// ```bash
/// cd packages/llm_ollama
/// dart test test/integration/all_integration_tests.dart
/// ```
///
/// Run all integration tests:
/// ```bash
/// dart test test/integration
/// ```
///
/// Run with integration tag:
/// ```bash
/// dart test -t integration
/// ```
///
/// Exclude from CI:
/// ```bash
/// dart test --exclude-tags integration
/// ```
///
/// Note: This test requires network access and the server to be available.
library;

import 'basic_chat_test.dart' as basic_chat;
import 'chat_history_test.dart' as chat_history;
import 'tool_calling_test.dart' as tool_calling;
import 'embeddings_test.dart' as embeddings;
import 'thinking_mode_test.dart' as thinking_mode;
import 'error_handling_test.dart' as error_handling;
import 'edge_cases_test.dart' as edge_cases;
import 'model_info_test.dart' as model_info;
import 'streaming_test.dart' as streaming;

void main() {
  basic_chat.main();
  chat_history.main();
  tool_calling.main();
  embeddings.main();
  thinking_mode.main();
  error_handling.main();
  edge_cases.main();
  model_info.main();
  streaming.main();
}
