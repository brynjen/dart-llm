/// llama.cpp backend implementation for LLM interactions.
///
/// This package provides local on-device inference using llama.cpp with GGUF models.
/// Supports Android, iOS, macOS, Windows, and Linux.
///
/// ## Architecture
///
/// This package follows the same pattern as `llm_ollama`:
/// - [LlamaCppRepository] - Model management (load, unload, discover, download)
/// - [LlamaCppChatRepository] - Chat operations (implements [LLMChatRepository])
///
/// ## Recommended Usage (Proper Separation of Concerns)
///
/// ```dart
/// import 'package:llm_llamacpp/llm_llamacpp.dart';
///
/// // Use LlamaCppRepository for model management
/// final modelRepo = LlamaCppRepository();
///
/// // Discover available models
/// final models = await modelRepo.discoverModels('/path/to/models');
/// print('Found ${models.length} models');
///
/// // Load a model
/// final model = await modelRepo.loadModel('/path/to/model.gguf');
///
/// // Use LlamaCppChatRepository for chat (pass the loaded model)
/// final chatRepo = LlamaCppChatRepository.withModel(model, modelRepo.bindings);
///
/// final stream = chatRepo.streamChat('model', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
///
/// // Cleanup
/// chatRepo.dispose();
/// modelRepo.unloadModel(model.path);
/// modelRepo.dispose();
/// ```
///
/// ## Legacy Usage (Backwards Compatible)
///
/// For simpler use cases, you can still load models directly via LlamaCppChatRepository:
///
/// ```dart
/// final chatRepo = LlamaCppChatRepository();
/// await chatRepo.loadModel('/path/to/model.gguf');
/// // ... use streamChat() ...
/// chatRepo.dispose();
/// ```
library;

// Re-export core types for convenience
export 'package:llm_core/llm_core.dart';

// Repositories
export 'src/llamacpp_chat_repository.dart';
export 'src/llamacpp_repository.dart';

// Model management
export 'src/llamacpp_model.dart' show LlamaCppModel, ModelLoadOptions;

// GGUF metadata
export 'src/gguf_metadata.dart';

// Model conversion
export 'src/model_converter.dart';

// Prompt templates
export 'src/prompt_template.dart';
