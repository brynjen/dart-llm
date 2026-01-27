import 'dart:io';

import 'package:llm_ollama/llm_ollama.dart';

/// CLI example demonstrating chat with Ollama.
///
/// Usage:
///   dart run example/cli_example.dart [model] [baseUrl]
///
/// Examples:
///   dart run example/cli_example.dart
///   dart run example/cli_example.dart qwen2:0.5b
///   dart run example/cli_example.dart llama3:8b http://localhost:11434
///
/// Requirements:
///   - Ollama running locally (default: http://localhost:11434)
///   - Model pulled in Ollama (e.g., `ollama pull qwen2:0.5b`)
Future<void> main(List<String> args) async {
  final model = args.isNotEmpty ? args[0] : 'qwen2:0.5b';
  final baseUrl = args.length > 1 ? args[1] : 'http://localhost:11434';
  final LLMLogger logger = DefaultLLMLogger('llm_ollama');
  logger.info('🦙 Ollama CLI Example\n');
  logger.info('Model: $model');
  logger.info('Base URL: $baseUrl\n');

  // Create chat repository
  final repo = OllamaChatRepository(baseUrl: baseUrl);

  try {
    // Verify connection by listing models (optional)
    logger.info('📋 Checking available models...');
    try {
      final ollamaRepo = OllamaRepository(baseUrl: baseUrl);
      final models = await ollamaRepo.models();
      if (models.isEmpty) {
        logger.info('⚠️  No models found. Pull a model first:');
        logger.info('   ollama pull $model\n');
      } else {
        logger.info('✅ Found ${models.length} model(s)\n');
      }
    } catch (e) {
      logger.info('⚠️  Could not connect to Ollama: $e');
      logger.info('   Make sure Ollama is running at $baseUrl\n');
    }

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
        final stream = repo.streamChat(
          model,
          messages: messages,
          think: false, // Set to true if using a thinking model
        );

        LLMChunk? lastChunk;
        await for (final chunk in stream) {
          final content = chunk.message?.content ?? '';
          stdout.write(content);
          fullResponse += content;
          lastChunk = chunk;

          // Show thinking tokens if available
          if (chunk.message?.thinking != null) {
            // Thinking tokens are typically shown separately
          }
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
