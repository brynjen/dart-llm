import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';

/// CLI example demonstrating local inference with llama.cpp.
///
/// Usage:
///   dart run example/cli_example.dart /path/to/model.gguf
///
/// Requirements:
///   - A GGUF model file (e.g., from Hugging Face)
///   - The native library, resolved automatically by `hook/build.dart`. For a
///     pure-Dart run, set `LLM_LLAMACPP_LIB_DIR` to the hook's output directory
///     if the loader cannot find it.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run example/cli_example.dart <model.gguf>');
    print('');
    print('Example:');
    print(
      '  dart run example/cli_example.dart ~/models/qwen2-0.5b-instruct-q4_k_m.gguf',
    );
    exit(1);
  }

  final modelPath = args[0];
  if (!File(modelPath).existsSync()) {
    print('Error: Model file not found: $modelPath');
    exit(1);
  }

  print('🦙 llama.cpp CLI Example\n');

  // Create model repository for model management
  final modelRepo = LlamaCppRepository();

  try {
    // Load the model
    print('📥 Loading model: $modelPath');
    final model = await modelRepo.loadModel(modelPath);
    print('✅ Model loaded successfully!\n');

    // Print model info
    print('Model Info:');
    print('  Vocab size: ${model.vocabSize}');
    print('  Context size (train): ${model.contextSizeTrain}');
    print('  Embedding size: ${model.embeddingSize}');
    print('');

    // Create chat repository with the loaded model
    final chatRepo = LlamaCppChatRepository.withModel(
      model,
      modelRepo.bindings,
      contextSize: 2048,
      nGpuLayers: 0, // Set > 0 if you have GPU support
    );

    // Interactive chat loop
    print('💬 Chat with the model (type "quit" to exit)\n');

    final messages = <LLMMessage>[
      LLMMessage(
        role: LLMRole.system,
        content: 'You are a helpful assistant. Answer questions concisely.',
      ),
    ];

    // Generation options (optional - uses defaults if not specified)
    const options = GenerationOptions(
      temperature: 0.7,
      topP: 0.9,
      maxTokens: 2048,
    );

    while (true) {
      stdout.write('You: ');
      final input = stdin.readLineSync();

      if (input == null || input.toLowerCase() == 'quit') {
        print('\nGoodbye! 👋');
        break;
      }

      if (input.isEmpty) continue;

      // Add user message
      messages.add(LLMMessage(role: LLMRole.user, content: input));

      // Stream response
      stdout.write('Assistant: ');
      String fullResponse = '';

      try {
        final stream = chatRepo.streamChatWithGenerationOptions(
          modelPath, // Model identifier (not used for loading, just for tracking)
          messages: messages,
          generationOptions: options,
        );

        await for (final chunk in stream) {
          final content = chunk.message?.content ?? '';
          stdout.write(content);
          fullResponse += content;
        }
        print('\n');

        // Add assistant response to history
        messages.add(
          LLMMessage(role: LLMRole.assistant, content: fullResponse),
        );
      } catch (e) {
        print('\n❌ Error: $e\n');
      }
    }

    // Cleanup chat repository
    chatRepo.dispose();
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  } finally {
    // Cleanup model repository
    modelRepo.dispose();
  }
}
