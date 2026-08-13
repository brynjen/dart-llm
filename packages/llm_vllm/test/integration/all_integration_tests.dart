/// Comprehensive integration test suite for llm_vllm against a remote VLLM server.
///
/// This test suite verifies that the package can successfully communicate with
/// a vLLM OpenAI-compatible server using the configured chat and embedding
/// models.
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
/// cd packages/llm_vllm
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
import 'concurrency_test.dart' as concurrency;
import 'tool_calling_test.dart' as tool_calling;
import 'tool_response_integration_test.dart' as tool_response;
import 'multi_turn_tool_calling_test.dart' as multi_turn_tools;
import 'embeddings_test.dart' as embeddings;
import 'structured_output_test.dart' as structured_output;
import 'thinking_mode_test.dart' as thinking_mode;
import 'error_handling_test.dart' as error_handling;
import 'edge_cases_test.dart' as edge_cases;
import 'model_info_test.dart' as model_info;
import 'streaming_test.dart' as streaming;
import 'stream_chunk_boundary_tool_loop_test.dart' as chunk_boundary;
import 'vllm_pool_integration_test.dart' as vllm_pool;

void main() {
  basic_chat.main();
  chat_history.main();
  concurrency.main();
  tool_calling.main();
  tool_response.main();
  multi_turn_tools.main();
  embeddings.main();
  structured_output.main();
  thinking_mode.main();
  error_handling.main();
  edge_cases.main();
  model_info.main();
  streaming.main();
  chunk_boundary.main();
  vllm_pool.main();
}
