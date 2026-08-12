import 'dart:io';

import 'package:llm_claude/llm_claude.dart';

/// CLI example demonstrating chat with Anthropic Claude.
///
/// Usage:
///   dart run example/cli_example.dart [model]
///
/// Examples:
///   dart run example/cli_example.dart
///   dart run example/cli_example.dart claude-sonnet-5
///
/// Requirements:
///   - `ANTHROPIC_API_KEY` set in the environment.
Future<void> main(List<String> args) async {
  final model = args.isNotEmpty ? args[0] : 'claude-opus-5';
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];

  if (apiKey == null || apiKey.isEmpty) {
    stdout.writeln('❌ ANTHROPIC_API_KEY is not set.');
    exit(1);
  }

  stdout.writeln('🤖 Claude CLI Example\n');
  stdout.writeln('Model: $model');

  // The request shape depends on the model: current models use adaptive
  // thinking and reject sampling parameters, older ones use a token budget.
  stdout.writeln('Request shape: ${claudeRequestShapeFor(model).name}\n');

  final repo = ClaudeChatRepository(apiKey: apiKey);

  try {
    stdout.writeln('💬 Chat with the model (type "quit" to exit)\n');

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

      messages.add(LLMMessage(role: LLMRole.user, content: input));

      stdout.write('Assistant: ');
      final buffer = StringBuffer();

      try {
        LLMChunk? lastChunk;
        await for (final chunk in repo.streamChat(model, messages: messages)) {
          final content = chunk.message?.content ?? '';
          stdout.write(content);
          buffer.write(content);
          lastChunk = chunk;
        }
        stdout.writeln('\n');

        // A refusal arrives as a successful response with empty content, so
        // it has to be checked explicitly rather than inferred from an error.
        if (lastChunk?.finishReason == LLMFinishReason.refusal) {
          stdout.writeln('  [The model declined this request]\n');
        } else if (lastChunk?.usage != null) {
          final usage = lastChunk!.usage!;
          stdout.writeln(
            '  [Tokens: prompt=${usage.promptTokens}, '
            'completion=${usage.completionTokens}]\n',
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
