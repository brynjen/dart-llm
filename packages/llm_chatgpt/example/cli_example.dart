import 'dart:io';

import 'package:llm_chatgpt/llm_chatgpt.dart';

/// CLI example demonstrating chat with OpenAI/ChatGPT.
///
/// Usage:
///   dart run example/cli_example.dart [model] [apiKey]
///
/// Examples:
///   OPENAI_API_KEY=your-key dart run example/cli_example.dart
///   OPENAI_API_KEY=your-key dart run example/cli_example.dart gpt-4o
///   dart run example/cli_example.dart gpt-4o-mini your-api-key
///
/// Requirements:
///   - OpenAI API key (set OPENAI_API_KEY env var or pass as argument)
///   - Internet connection
Future<void> main(List<String> args) async {
  final model = args.isNotEmpty ? args[0] : 'gpt-4o-mini';
  final LLMLogger logger = DefaultLLMLogger('llm_chatgpt');

  // Get API key from environment or arguments
  String? apiKey;
  if (args.length > 1) {
    apiKey = args[1];
  } else {
    apiKey =
        Platform.environment['OPENAI_API_KEY'] ??
        Platform.environment['CHATGPT_ACCESS_TOKEN'];
  }

  if (apiKey == null || apiKey.isEmpty) {
    logger.info('❌ Error: OpenAI API key required');
    logger.info('');
    logger.info('Set OPENAI_API_KEY environment variable:');
    logger.info('  export OPENAI_API_KEY=your-api-key');
    logger.info('  dart run example/cli_example.dart');
    logger.info('');
    logger.info('Or pass as argument:');
    logger.info('  dart run example/cli_example.dart $model your-api-key');
    exit(1);
  }

  logger.info('🤖 ChatGPT/OpenAI CLI Example\n');
  logger.info('Model: $model');
  logger.info('Base URL: https://api.openai.com\n');

  // Create chat repository
  final repo = ChatGPTChatRepository(apiKey: apiKey);

  try {
    // Interactive chat loop
    logger.info('💬 Chat with the model (type "quit" to exit)\n');

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
        logger.info('\nGoodbye! 👋');
        break;
      }

      if (input.isEmpty) continue;

      // Add user message
      messages.add(LLMMessage(role: LLMRole.user, content: input));

      // Stream response
      stdout.write('Assistant: ');
      String fullResponse = '';

      try {
        final stream = repo.streamChat(model, messages: messages);

        LLMChunk? lastChunk;
        await for (final chunk in stream) {
          final content = chunk.message?.content ?? '';
          stdout.write(content);
          fullResponse += content;
          lastChunk = chunk;
        }
        logger.info('\n');

        // Show token counts if available
        if (lastChunk != null && lastChunk.done == true) {
          if (lastChunk.promptEvalCount != null ||
              lastChunk.evalCount != null) {
            logger.info(
              '  [Tokens: prompt=${lastChunk.promptEvalCount ?? '?'}, eval=${lastChunk.evalCount ?? '?'}]\n',
            );
          }
        }

        // Add assistant response to history
        messages.add(
          LLMMessage(role: LLMRole.assistant, content: fullResponse),
        );
      } catch (e) {
        logger.info('\n❌ Error: $e\n');
        // Remove the user message if there was an error
        messages.removeLast();
      }
    }
  } catch (e) {
    logger.info('❌ Error: $e');
    exit(1);
  }
}
