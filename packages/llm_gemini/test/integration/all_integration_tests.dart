/// Comprehensive integration test suite for llm_gemini against the Gemini API.
///
/// This test suite verifies that the package can successfully communicate with
/// the Google Gemini API using gemini-3.5-flash-lite by default for chat and
/// gemini-embedding-001 for embeddings.
///
/// The test suite is organized into categories for easier navigation:
/// - Basic Chat Tests - Streaming and non-streaming responses
/// - Chat History Tests - Multi-turn conversations, context preservation
/// - Tool Calling Tests - Single tools, multiple tools, tool chains
/// - Structured Output Tests - JSON schema output
/// - Embeddings Tests - Single and batch embeddings, similarity, dimensions
/// - Error Handling Tests - Invalid API keys, invalid models, network errors
/// - Edge Case Tests - Unicode, JSON content, concurrent requests
/// - Streaming Behavior Tests - Chunk ordering, done flags, token counts
///
/// Run this test:
/// ```bash
/// cd packages/llm_gemini
/// GEMINI_API_KEY=your-key dart test test/integration/all_integration_tests.dart
/// ```
///
/// Run all integration tests:
/// ```bash
/// GEMINI_API_KEY=your-key dart test test/integration
/// ```
///
/// Run with integration tag:
/// ```bash
/// GEMINI_API_KEY=your-key dart test -t integration
/// ```
///
/// Exclude from CI:
/// ```bash
/// dart test --exclude-tags integration
/// ```
///
/// Note: This test requires network access and a valid Gemini API key.
/// Set GEMINI_API_KEY environment variable.
library;

import 'basic_chat_test.dart' as basic_chat;
import 'chat_history_test.dart' as chat_history;
import 'tool_calling_test.dart' as tool_calling;
import 'structured_output_test.dart' as structured_output;
import 'embeddings_test.dart' as embeddings;
import 'error_handling_test.dart' as error_handling;
import 'edge_cases_test.dart' as edge_cases;
import 'streaming_test.dart' as streaming;

void main() {
  basic_chat.main();
  chat_history.main();
  tool_calling.main();
  structured_output.main();
  embeddings.main();
  error_handling.main();
  edge_cases.main();
  streaming.main();
}
