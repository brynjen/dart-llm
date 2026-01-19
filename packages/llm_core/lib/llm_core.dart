/// Core abstractions for LLM (Large Language Model) interactions.
///
/// This package provides the foundational interfaces and models used by
/// LLM backend implementations such as Ollama, ChatGPT, and llama.cpp.
///
/// Example usage:
/// ```dart
/// import 'package:llm_core/llm_core.dart';
///
/// // Use with any LLMChatRepository implementation
/// void chat(LLMChatRepository repo) async {
///   final stream = repo.streamChat('model-name', messages: [
///     LLMMessage(role: LLMRole.user, content: 'Hello!')
///   ]);
///   await for (final chunk in stream) {
///     print(chunk.message?.content ?? '');
///   }
/// }
/// ```
library;

// Models
export 'src/llm_message.dart';
export 'src/llm_chunk.dart';
export 'src/llm_response.dart';
export 'src/llm_embedding.dart';

// Tools
export 'src/tool/llm_tool.dart';
export 'src/tool/llm_tool_param.dart';
export 'src/tool/llm_tool_call.dart';

// Repository interface
export 'src/llm_chat_repository.dart';

// Exceptions
export 'src/exceptions.dart';

// Logging
export 'src/llm_logger.dart';

// Retry configuration
export 'src/retry_config.dart';
export 'src/retry_util.dart';

// Timeout configuration
export 'src/timeout_config.dart';

// Stream chat options
export 'src/stream_chat_options.dart';

// Validation
export 'src/validation.dart';

// Metrics
export 'src/llm_metrics.dart';

