import 'dart:async';

import 'package:llm_core/src/llm_chat_repository.dart';
import 'package:llm_core/src/llm_message.dart';
import 'package:llm_core/src/llm_metrics.dart';
import 'package:llm_core/src/llm_response.dart';
import 'package:llm_core/src/response_cache.dart';
import 'package:llm_core/src/stream_chat_options.dart';
import 'package:llm_core/src/tool/llm_tool.dart';

/// Shared cache and metrics behavior for repository implementations.
mixin LLMRepositoryFeatures on LLMChatRepository {
  /// Optional response cache.
  ResponseCache? get responseCache => null;

  /// Optional metrics collector.
  LLMMetrics? get metrics => null;

  @override
  Future<LLMResponse> chatResponse(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
  }) async {
    final resolvedOptions = options ?? const LLMChatOptions();
    final cache = responseCache;
    final cacheKey = resolvedOptions.useCache && cache != null
        ? CacheKeyGenerator.generateKey(
            model,
            messages,
            optionsHash: CacheKeyGenerator.optionsHash(
              resolvedOptions,
              think: think,
              tools: tools,
            ),
          )
        : null;

    if (cache != null && cacheKey != null) {
      final cached = await cache.get(cacheKey);
      if (cached != null) return cached;
    }

    final startedAt = DateTime.now();
    try {
      final response = await super.chatResponse(
        model,
        messages: messages,
        think: think,
        tools: tools,
        extra: extra,
        options: options,
      );

      if (cache != null && cacheKey != null) {
        await cache.put(cacheKey, response, ttl: resolvedOptions.cacheTtl);
      }
      if (resolvedOptions.recordMetrics) {
        _recordSuccess(model, response, DateTime.now().difference(startedAt));
      }
      return response;
    } catch (error) {
      if (resolvedOptions.recordMetrics) {
        _recordFailure(model, error, DateTime.now().difference(startedAt));
      }
      rethrow;
    }
  }

  void _recordSuccess(String model, LLMResponse response, Duration latency) {
    final collector = metrics;
    if (collector == null) return;
    collector
      ..recordRequest(model: model, success: true)
      ..recordLatency(model: model, latency: latency)
      ..recordTokens(
        model: model,
        promptTokens: response.promptEvalCount,
        generatedTokens: response.evalCount,
      );
  }

  void _recordFailure(String model, Object error, Duration latency) {
    final collector = metrics;
    if (collector == null) return;
    collector
      ..recordRequest(model: model, success: false)
      ..recordLatency(model: model, latency: latency)
      ..recordError(model: model, errorType: error.runtimeType.toString());
  }
}
