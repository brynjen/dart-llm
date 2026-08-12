import 'dart:io';

import 'package:llm_vllm/llm_vllm.dart';

/// CLI example demonstrating chat with VLLM.
///
/// Usage:
///   dart run example/cli_example.dart [model] [baseUrl] [apiKey]
///
/// Examples:
///   dart run example/cli_example.dart
///   dart run example/cli_example.dart Qwen/Qwen3-0.6B
///   dart run example/cli_example.dart Qwen/Qwen3-0.6B http://localhost:8000
///
/// Requirements:
///   - vLLM running locally (default: http://localhost:8000)
Future<void> main(List<String> args) async {
  final model = args.isNotEmpty ? args[0] : 'Qwen/Qwen3-0.6B';
  final baseUrl = args.length > 1 ? args[1] : 'http://localhost:8000';
  final apiKey = args.length > 2
      ? args[2]
      : Platform.environment['VLLM_API_KEY'];
  stdout.writeln('🦙 VLLM CLI Example\n');
  stdout.writeln('Model: $model');
  stdout.writeln('Base URL: $baseUrl\n');

  // Create chat repository
  final repo = VLLMChatRepository(baseUrl: baseUrl, apiKey: apiKey);

  try {
    // Verify connection by listing models (optional)
    stdout.writeln('📋 Checking available models...');
    try {
      final vllmRepo = VLLMRepository(baseUrl: baseUrl, apiKey: apiKey);
      final models = await vllmRepo.models();
      if (models.isEmpty) {
        stdout.writeln('⚠️  No models reported by /v1/models.\n');
      } else {
        stdout.writeln('✅ Found ${models.length} model(s)\n');
      }
    } catch (e) {
      stdout.writeln('⚠️  Could not connect to VLLM: $e');
      stdout.writeln('   Make sure VLLM is running at $baseUrl\n');
    }

    // Interactive chat loop
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
        stdout.writeln('\n');

        // Show token counts if available
        if (lastChunk != null && lastChunk.done == true) {
          if (lastChunk.promptEvalCount != null ||
              lastChunk.evalCount != null) {
            stdout.writeln(
              '  [Tokens: prompt=${lastChunk.promptEvalCount ?? '?'}, eval=${lastChunk.evalCount ?? '?'}]\n',
            );
          }
        }

        // Add assistant response to history
        messages.add(
          LLMMessage(role: LLMRole.assistant, content: fullResponse),
        );
      } catch (e) {
        stdout.writeln('\n❌ Error: $e\n');
        // Remove the user message if there was an error
        messages.removeLast();
      }
    }
  } catch (e) {
    stdout.writeln('❌ Error: $e');
    exit(1);
  }
}
