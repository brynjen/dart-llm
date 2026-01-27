import 'dart:async';

import 'package:llm_core/llm_core.dart';

/// Mock implementation of [LLMChatRepository] for testing.
///
/// This mock allows you to control responses, simulate errors, and test
/// various scenarios without making actual API calls.
///
/// Example:
/// ```dart
/// final mock = MockLLMChatRepository();
/// mock.setResponse('Hello, world!');
/// final stream = mock.streamChat('test-model', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello')
/// ]);
/// ```
class MockLLMChatRepository extends LLMChatRepository {
  String? _responseContent;
  List<LLMToolCall>? _toolCalls;
  Exception? _error;
  Duration _delay = Duration.zero;
  int _promptTokens = 10;
  int _generatedTokens = 5;

  /// Set the response content to return.
  void setResponse(String content) {
    _responseContent = content;
    _error = null;
  }

  /// Set tool calls to return.
  void setToolCalls(List<LLMToolCall> toolCalls) {
    _toolCalls = toolCalls;
  }

  /// Set an error to throw.
  void setError(Exception error) {
    _error = error;
    _responseContent = null;
  }

  /// Set delay before responding.
  void setDelay(Duration delay) {
    _delay = delay;
  }

  /// Set token counts.
  void setTokenCounts({int? promptTokens, int? generatedTokens}) {
    if (promptTokens != null) _promptTokens = promptTokens;
    if (generatedTokens != null) _generatedTokens = generatedTokens;
  }

  @override
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    StreamChatOptions? options,
  }) async* {
    if (_delay > Duration.zero) {
      await Future.delayed(_delay);
    }

    if (_error != null) {
      throw _error!;
    }

    // Emit content chunks
    if (_responseContent != null) {
      final words = _responseContent!.split(' ');
      for (int i = 0; i < words.length; i++) {
        final isLast = i == words.length - 1;
        yield LLMChunk(
          model: model,
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: i == 0 ? words[i] : ' ${words[i]}',
            role: LLMRole.assistant,
            toolCalls: isLast && _toolCalls != null && _toolCalls!.isNotEmpty
                ? _toolCalls
                : null,
          ),
          done: isLast,
          promptEvalCount: isLast ? _promptTokens : null,
          evalCount: isLast ? _generatedTokens : null,
        );
      }
    }
  }

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    if (_delay > Duration.zero) {
      await Future.delayed(_delay);
    }

    if (_error != null) {
      throw _error!;
    }

    // Return mock embeddings (128-dimensional vectors)
    return messages.map((msg) {
      return LLMEmbedding(
        model: model,
        embedding: List.generate(128, (i) => (i * 0.01) % 1.0),
        promptEvalCount: msg.split(' ').length,
      );
    }).toList();
  }
}
