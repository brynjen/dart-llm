/// VLLM backend implementation for LLM interactions.
///
/// This package provides an VLLM-specific implementation of [LLMChatRepository]
/// with support for streaming chat, embeddings, tool calling, vision, and model management.
///
/// Example usage:
/// ```dart
/// import 'package:llm_vllm/llm_vllm.dart';
///
/// final repo = VLLMChatRepository(baseUrl: 'http://localhost:8000');
/// final stream = repo.streamChat('qwen3:0.6b', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
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
        reservedVllmParams,
        vllmParamAliases,
        legacyGuidedKeys,
        VllmParamIssue,
        VllmParamValidationError,
        validateVllmParams,
        normalizeVllmParam,
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
export 'src/dto/vllm_response.dart';
export 'src/dto/vllm_chunk.dart';
export 'src/dto/vllm_choice.dart';
export 'src/dto/vllm_tool_call.dart';
export 'src/dto/vllm_usage.dart';
export 'src/dto/vllm_embedding_response.dart';
