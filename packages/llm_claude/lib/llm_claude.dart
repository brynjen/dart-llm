/// Anthropic Claude API backend for LLM interactions.
///
/// Provides a Claude-specific implementation of [LLMChatRepository]
/// with support for streaming chat and tool calling via the Anthropic Messages API.
///
/// Note: The Claude API does not support embeddings. Use a dedicated embedding
/// service instead.
///
/// Example usage:
/// ```dart
/// import 'package:llm_claude/llm_claude.dart';
///
/// final repo = ClaudeChatRepository(apiKey: 'your-api-key');
/// final stream = repo.streamChat('claude-opus-5', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
library;

// Re-export core types for convenience
export 'package:llm_core/llm_core.dart';

// Repository
export 'src/claude_chat_repository.dart';
export 'src/claude_chat_repository_builder.dart';

// Per-model request-shape rules (adaptive thinking, sampling parameters,
// structured outputs) — exposed so callers can branch on model capability.
export 'src/claude_model_features.dart'
    show
        ClaudeRequestShape,
        claudeRequestShapeFor,
        claudeRejectsSamplingParams,
        claudeSupportsAdaptiveThinking,
        claudeSupportsStructuredOutputs;

// DTOs (for advanced usage)
export 'src/dto/claude_chunk.dart';
export 'src/dto/claude_usage.dart';
