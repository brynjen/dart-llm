/// Comprehensive integration test suite for llm_chatgpt against OpenAI API.
///
/// This test suite verifies that the package can successfully communicate with
/// the OpenAI API using the gpt-4o-mini model for chat and text-embedding-3-small
/// for embeddings.
///
/// The test suite is organized into categories for easier navigation:
/// - Basic Chat Tests - Streaming and non-streaming responses
/// - Chat History Tests - Multi-turn conversations, context preservation
/// - Tool Calling Tests - Single tools, multiple tools, tool chains
/// - Embedding Tests - Single embeddings, batch embeddings, similarity
/// - Error Handling Tests - Invalid API keys, invalid models, network errors
/// - Edge Case Tests - Empty messages, unicode, concurrent requests
/// - Streaming Behavior Tests - Chunk ordering, done flags
///
/// Run this test:
/// ```bash
/// cd packages/llm_chatgpt
/// OPENAI_API_KEY=your-key dart test test/integration/all_integration_tests.dart
/// ```
///
/// Run all integration tests:
/// ```bash
/// OPENAI_API_KEY=your-key dart test test/integration
/// ```
///
/// Run with integration tag:
/// ```bash
/// OPENAI_API_KEY=your-key dart test -t integration
/// ```
///
/// Exclude from CI:
/// ```bash
/// dart test --exclude-tags integration
/// ```
///
/// Note: This test requires network access and a valid OpenAI API key.
/// Set OPENAI_API_KEY or CHATGPT_ACCESS_TOKEN environment variable.
library;

import 'basic_chat_test.dart' as basic_chat;
import 'chat_history_test.dart' as chat_history;
import 'tool_calling_test.dart' as tool_calling;
import 'embeddings_test.dart' as embeddings;
import 'error_handling_test.dart' as error_handling;
import 'edge_cases_test.dart' as edge_cases;
import 'streaming_test.dart' as streaming;

void main() {
  basic_chat.main();
  chat_history.main();
  tool_calling.main();
  embeddings.main();
  error_handling.main();
  edge_cases.main();
  streaming.main();
}
