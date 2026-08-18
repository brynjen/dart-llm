import 'dart:io';

import 'package:llm_gemini/llm_gemini.dart';

/// CLI example demonstrating chat with Google Gemini.
///
/// Usage:
///   dart run example/cli_example.dart [model]
///
/// Examples:
///   dart run example/cli_example.dart
///   dart run example/cli_example.dart gemini-3.5-flash
///
/// Requirements:
///   - `GEMINI_API_KEY` set in the environment.
Future<void> main(List<String> args) async {
  final model = args.isNotEmpty ? args[0] : 'gemini-3.5-flash-lite';
  final apiKey = Platform.environment['GEMINI_API_KEY'];

  if (apiKey == null || apiKey.isEmpty) {
    stdout.writeln('❌ GEMINI_API_KEY is not set.');
    exit(1);
  }

  stdout.writeln('✨ Gemini CLI Example\n');
  stdout.writeln('Model: $model');
  // Chat runs on the Interactions API, which takes the key as a header rather
  // than a query parameter, and is stateless unless you opt into
  // `previous_interaction_id`.
  stdout.writeln('Endpoint: POST /v1beta/interactions\n');

  final repo = GeminiChatRepository(apiKey: apiKey);

  try {
    stdout.writeln('💬 Chat with the model (type "quit" to exit)\n');
    stdout.writeln(
      'Prefix a message with "think:" to request thought summaries.\n',
    );

    final messages = <LLMMessage>[
      LLMMessage(
        role: LLMRole.system,
        content: 'You are a helpful assistant. Answer questions concisely.',
      ),
    ];

    while (true) {
      stdout.write('You: ');
      final input = stdin.readLineSync();

      if (input == null || input.toLowerCase() == 'quit') {
        stdout.writeln('\nGoodbye! 👋');
        break;
      }
      if (input.isEmpty) continue;

      final think = input.startsWith('think:');
      final prompt = think ? input.substring('think:'.length).trim() : input;
      if (prompt.isEmpty) continue;

      messages.add(LLMMessage(role: LLMRole.user, content: prompt));

      final buffer = StringBuffer();
      var thinkingHeaderWritten = false;
      var answerHeaderWritten = false;

      try {
        LLMChunk? lastChunk;
        final stream = repo.streamChat(model, messages: messages, think: think);

        await for (final chunk in stream) {
          // Thought summaries arrive on `thinking`, kept separate from the
          // answer text on `content`.
          final thinking = chunk.message?.thinking;
          if (thinking != null && thinking.isNotEmpty) {
            if (!thinkingHeaderWritten) {
              stdout.write('Thinking: ');
              thinkingHeaderWritten = true;
            }
            stdout.write(thinking);
          }

          final content = chunk.message?.content ?? '';
          if (content.isNotEmpty) {
            if (!answerHeaderWritten) {
              if (thinkingHeaderWritten) stdout.writeln('\n');
              stdout.write('Assistant: ');
              answerHeaderWritten = true;
            }
            stdout.write(content);
            buffer.write(content);
          }

          lastChunk = chunk;
        }
        stdout.writeln('\n');

        // A refusal arrives as a successful response with empty content, so it
        // has to be checked explicitly rather than inferred from an error.
        if (lastChunk?.finishReason == LLMFinishReason.refusal) {
          stdout.writeln('  [The model declined this request]\n');
        } else if (lastChunk?.usage != null) {
          final usage = lastChunk!.usage!;
          final reasoning = usage.reasoningTokens;
          stdout.writeln(
            '  [Tokens: prompt=${usage.promptTokens}, '
            'completion=${usage.completionTokens}'
            '${reasoning != null ? ', reasoning=$reasoning' : ''}]\n',
          );
        }

        messages.add(
          LLMMessage(role: LLMRole.assistant, content: buffer.toString()),
        );
      } catch (e) {
        stdout.writeln('\n❌ Error: $e\n');
        messages.removeLast();
      }
    }
  } finally {
    repo.close();
  }
}
