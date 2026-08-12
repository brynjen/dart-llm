import 'dart:io';

import 'package:llm_core/llm_core.dart';

/// Demonstrates programming against [LLMChatRepository] rather than a specific
/// backend, so the provider can be swapped without touching call sites.
///
/// `llm_core` ships no backend, so this example uses a small in-memory fake in
/// place of a real one. Substitute any backend package
/// (`VLLMChatRepository`, `ClaudeChatRepository`, …) for the same result.
///
/// Usage:
///   dart run example/provider_agnostic_example.dart
Future<void> main() async {
  final LLMChatRepository repo = _EchoRepository();

  stdout.writeln('Streaming:');
  await for (final chunk in repo.streamChat(
    'fake-model',
    messages: [LLMMessage(role: LLMRole.user, content: 'Hello!')],
    options: const LLMChatOptions(temperature: 0.2, maxOutputTokens: 64),
  )) {
    stdout.writeln('  chunk: ${chunk.message?.content ?? ''}');
  }

  final response = await repo.chatResponse(
    'fake-model',
    messages: [LLMMessage(role: LLMRole.user, content: 'Hello again!')],
  );

  stdout.writeln('\nAggregated: ${response.content}');
  stdout.writeln('Finish reason: ${response.finishReason}');

  // A refusal is a *successful* response with empty content, so it has to be
  // checked explicitly rather than caught as an error.
  if (response.finishReason == LLMFinishReason.refusal) {
    stdout.writeln('The provider declined this request.');
  }
}

/// A minimal [LLMChatRepository] that echoes the last user message back one
/// word at a time. Stands in for a real backend.
class _EchoRepository extends LLMChatRepository {
  @override
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
  }) async* {
    Validation.validateModelName(model);
    Validation.validateMessages(messages);

    final prompt = messages.lastWhere((m) => m.role == LLMRole.user).content!;
    final words = prompt.split(' ');

    for (var i = 0; i < words.length; i++) {
      yield LLMChunk(
        model: model,
        createdAt: DateTime.now(),
        done: false,
        message: LLMChunkMessage(
          content: i == 0 ? words[i] : ' ${words[i]}',
          role: LLMRole.assistant,
        ),
      );
    }

    yield LLMChunk(
      model: model,
      createdAt: DateTime.now(),
      done: true,
      finishReason: LLMFinishReason.stop,
      usage: LLMUsage(
        promptTokens: words.length,
        completionTokens: words.length,
      ),
      message: LLMChunkMessage(content: null, role: LLMRole.assistant),
    );
  }

  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async =>
      throw UnsupportedError('The echo repository does not support embeddings');
}
