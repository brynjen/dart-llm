/// vLLM backend implementation for LLM interactions.
///
/// This package provides a vLLM-specific implementation of [LLMChatRepository]
/// with support for streaming chat, embeddings, tool calling, reasoning,
/// structured output, validated backend options, and multi-instance pooling.
/// Vision requires a multimodal model; images pass through the
/// OpenAI-compatible message content.
///
/// Example usage:
/// ```dart
/// import 'package:llm_vllm/llm_vllm.dart';
///
/// final repo = VLLMChatRepository(baseUrl: 'http://localhost:8000');
/// final stream = repo.streamChat('Qwen/Qwen3-0.6B', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// repo.close();
/// ```
library;

// Re-export core types for convenience
export 'package:llm_core/llm_core.dart';

// Repositories
export 'src/vllm_chat_repository.dart';
export 'src/vllm_chat_repository_builder.dart';
export 'src/vllm_repository.dart';

// vLLM-specific request options
export 'src/vllm_base_url.dart' show normalizeVllmBaseUrl, vllmEndpoint;
export 'src/vllm_sampling_options.dart' show VLLMSamplingOptions;
export 'src/vllm_structured_outputs.dart' show VLLMStructuredOutputs;
export 'src/vllm_params.dart'
    show
        knownVllmChatParams,
        knownVllmEmbeddingParams,
        reservedVllmParams,
        reservedVllmEmbeddingParams,
        vllmParamAliases,
        legacyGuidedKeys,
        VllmParamIssue,
        VllmParamValidationError,
        validateVllmParams,
        normalizeVllmParam,
        normalizeVllmParams,
        suggestVllmParam;

// Pool — multi-instance orchestration
export 'src/pool/vllm_pool.dart'
    show VLLMPool, VLLMNoEligibleInstanceException, VLLMQueueFullException;
export 'src/pool/vllm_pool_builder.dart';
export 'src/pool/vllm_instance_config.dart';
export 'src/pool/vllm_model_config.dart';
export 'src/pool/health_check_config.dart';
export 'src/pool/pool_stats.dart';
export 'src/pool/semaphore.dart' show VLLMQueueTimeoutException;

// DTOs (for advanced usage)
export 'src/dto/vllm_model.dart';
export 'src/dto/vllm_chunk.dart';
export 'src/dto/vllm_tool_call.dart';
export 'src/dto/vllm_usage.dart';
export 'src/dto/vllm_embedding_response.dart';
