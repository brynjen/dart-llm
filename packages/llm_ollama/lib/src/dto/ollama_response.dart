import 'dart:convert';

import 'package:llm_core/llm_core.dart';

/// Ollama-specific response from a chat completion.
class OllamaResponse extends LLMResponse {
  OllamaResponse({
    required super.model,
    required super.createdAt,
    required super.role,
    required super.content,
    required super.done,
    required super.doneReason,
    required super.promptEvalCount,
    required super.evalCount,
    required super.toolCalls,
  });
}

/// Ollama-specific streaming chunk.
class OllamaChunk extends LLMChunk {
  OllamaChunk({
    required super.model,
    required super.createdAt,
    required super.message,
    super.done,
    super.promptEvalCount,
    super.evalCount,
    super.finishReason,
  });

  factory OllamaChunk.fromJson(Map<String, dynamic> json) {
    return OllamaChunk(
      model: json['model'],
      createdAt: DateTime.parse(json['created_at']),
      message: json['message'] != null
          ? OllamaChunkMessage.fromJson(json['message'])
          : null,
      done: json['done'],
      promptEvalCount: json['prompt_eval_count'],
      evalCount: json['eval_count'],
      finishReason: json['done_reason'] != null
          ? LLMFinishReason.fromProvider(json['done_reason'] as String?)
          : null,
    );
  }
}

/// Ollama-specific chunk message.
class OllamaChunkMessage extends LLMChunkMessage {
  OllamaChunkMessage({
    required super.content,
    required super.role,
    super.thinking,
    super.toolCalls,
  });

  factory OllamaChunkMessage.fromJson(Map<String, dynamic> json) {
    LLMRole? role;
    if (json['role'] != null) {
      try {
        role = LLMRole.values.firstWhere((e) => e.name == json['role']);
      } catch (e) {
        role = null;
      }
    }

    // Parse tool calls
    List<LLMToolCall>? toolCalls;
    if (json['tool_calls'] != null) {
      final toolCallsJson = json['tool_calls'] as List<dynamic>;
      toolCalls = <LLMToolCall>[];

      for (var i = 0; i < toolCallsJson.length; i++) {
        final rawToolCall = toolCallsJson[i] as Map<String, dynamic>;
        final functionJson = rawToolCall['function'] as Map<String, dynamic>;

        final argumentsValue = functionJson['arguments'];
        // If arguments is already a string, use it directly; otherwise encode it
        final arguments = argumentsValue is String
            ? argumentsValue
            : jsonEncode(argumentsValue);

        // Prefer an explicit id from the backend when available; otherwise
        // synthesize a deterministic, non-empty id so that llm_core can
        // safely use it as toolCallId for tool messages.
        final rawId = rawToolCall['id'];
        final id = (rawId is String && rawId.isNotEmpty)
            ? rawId
            : 'tool_${i}_${functionJson['name']}';

        toolCalls.add(
          LLMToolCall(id: id, name: functionJson['name'], arguments: arguments),
        );
      }
    }

    // Handle thinking content embedded in content field (when tools are used)
    String? content = json['content'];
    String? thinking = json['thinking'];

    if (content != null && content.contains('<think>')) {
      // Extract thinking from content
      final thinkMatch = RegExp(
        r'<think>(.*?)</think>',
        dotAll: true,
      ).firstMatch(content);
      if (thinkMatch != null) {
        thinking = thinkMatch.group(1)?.trim();
        // Remove thinking tags from content
        content = content
            .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
            .trim();
      }
    }

    return OllamaChunkMessage(
      content: content,
      role: role,
      thinking: thinking,
      toolCalls: toolCalls,
    );
  }
}
