import 'dart:async';
import 'dart:isolate';

import 'package:llm_core/llm_core.dart' show
    LLMApiException,
    LLMChatRepository,
    LLMChunk,
    LLMChunkMessage,
    LLMEmbedding,
    LLMLogger,
    DefaultLLMLogger,
    LLMLogLevel,
    LLMMessage,
    LLMRole,
    LLMTool,
    ModelLoadException,
    StreamChatOptions,
    Validation,
    VisionNotSupportedException;
import 'package:llm_llamacpp/src/backend_initializer.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/embedding_isolate.dart';
import 'package:llm_llamacpp/src/error_translator.dart';
import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/generation_options.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/llamacpp_model.dart';
import 'package:llm_llamacpp/src/llamacpp_repository.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/prompt_template.dart';
import 'package:llm_llamacpp/src/tool_call_stream_handler.dart';
import 'package:llm_llamacpp/src/tool_executor.dart';

/// Repository for chatting with llama.cpp models locally.
///
/// This repository implements the [LLMChatRepository] contract and focuses
/// solely on chat operations. Model management (loading, unloading, discovery)
/// should be handled by [LlamaCppRepository].
///
/// Example with model from repository:
/// ```dart
/// // Use LlamaCppRepository for model management
/// final modelRepo = LlamaCppRepository();
/// final model = await modelRepo.loadModel('/path/to/model.gguf');
///
/// // Use LlamaCppChatRepository for chat
/// final chatRepo = LlamaCppChatRepository.withModel(model, modelRepo.bindings);
///
/// final stream = chatRepo.streamChat('model', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
/// ```
///
/// Example with LoRA adapter:
/// ```dart
/// final modelRepo = LlamaCppRepository();
/// final model = await modelRepo.loadModel('/path/to/model.gguf');
/// final lora = modelRepo.loadLora('/path/to/lora.gguf', model);
///
/// // Create chat repo with LoRA
/// final chatRepo = LlamaCppChatRepository.withModel(
///   model,
///   modelRepo.bindings,
///   loraPath: lora.path,
///   loraScale: 0.8,
/// );
///
/// // Or set LoRA at runtime
/// chatRepo.setLora(lora.path, scale: 0.5);
/// chatRepo.clearLora();
/// ```
///
/// Example standalone (loads model internally - for backwards compatibility):
/// ```dart
/// final chatRepo = LlamaCppChatRepository();
/// await chatRepo.loadModel('/path/to/model.gguf');
///
/// final stream = chatRepo.streamChat('model', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
///
/// chatRepo.dispose();
/// ```
class LlamaCppChatRepository extends LLMChatRepository {
  /// Logger instance for this package.
  static final LLMLogger _log = DefaultLLMLogger('llm_llamacpp');

  /// Creates a chat repository with default settings.
  ///
  /// Load a model before calling [streamChat] using [LlamaCppRepository.loadModel]
  /// or use [LlamaCppChatRepository.withModel] for proper separation of concerns.
  ///
  /// For managing models, use [LlamaCppRepository] directly.
  LlamaCppChatRepository({
    this.contextSize = 4096,
    this.batchSize = 512,
    this.threads,
    this.nGpuLayers = 0,
    this.maxToolAttempts = 25,
    PromptTemplate? template,
    String? loraPath,
    double loraScale = 1.0,
  }) : _template = template,
       _loraPath = loraPath,
       _loraScale = loraScale,
       _ownsModel = true;

  /// Creates a chat repository with an already-loaded model.
  ///
  /// This is the preferred constructor when using [LlamaCppRepository] for
  /// model management, as it maintains proper separation of concerns.
  ///
  /// [model] - A model loaded via [LlamaCppRepository.loadModel].
  /// [bindings] - The bindings from [LlamaCppRepository.bindings].
  /// [loraPath] - Optional path to a LoRA adapter file to apply during inference.
  /// [loraScale] - Scale factor for the LoRA adapter (0.0 to 1.0+). Default is 1.0.
  LlamaCppChatRepository.withModel(
    LlamaCppModel model,
    LlamaBindings bindings, {
    this.contextSize = 4096,
    this.batchSize = 512,
    this.threads,
    this.nGpuLayers = 0,
    this.maxToolAttempts = 25,
    PromptTemplate? template,
    String? loraPath,
    double loraScale = 1.0,
  }) : _template = template,
       _model = model,
       _bindings = bindings,
       _backendInitialized = true,
       _loraPath = loraPath,
       _loraScale = loraScale,
       _ownsModel = false;
  
  /// Creates a chat repository with a model path for lazy loading.
  ///
  /// This is the recommended constructor for Android. Unlike [loadModel] which
  /// loads the model in the main isolate, this constructor only stores the path.
  /// The model is loaded in the inference isolate, avoiding FFI issues that can
  /// occur when llama.cpp functions are called from multiple Dart isolates.
  ///
  /// [modelPath] - Path to the GGUF model file.
  /// [loraPath] - Optional path to a LoRA adapter file to apply during inference.
  /// [loraScale] - Scale factor for the LoRA adapter (0.0 to 1.0+). Default is 1.0.
  LlamaCppChatRepository.withModelPath(
    String modelPath, {
    this.contextSize = 4096,
    this.batchSize = 512,
    this.threads,
    this.nGpuLayers = 0,
    this.maxToolAttempts = 25,
    PromptTemplate? template,
    String? loraPath,
    double loraScale = 1.0,
  }) : _template = template,
       _modelPath = modelPath,
       _loraPath = loraPath,
       _loraScale = loraScale,
       _ownsModel = false;

  /// The context size (number of tokens).
  final int contextSize;

  /// The batch size for processing.
  final int batchSize;

  /// Number of threads to use (null = auto-detect).
  final int? threads;

  /// Number of layers to offload to GPU.
  final int nGpuLayers;

  /// Maximum number of tool calling attempts.
  final int maxToolAttempts;

  /// Whether this repository owns and should dispose the model.
  final bool _ownsModel;

  PromptTemplate? _template;
  LlamaBindings? _bindings;
  LlamaCppModel? _model;
  bool _backendInitialized = false;
  
  /// Model path for lazy loading (model is loaded in inference isolate, not main isolate)
  /// This is used when the repository is created with withModelPath constructor.
  String? _modelPath;

  // LoRA configuration
  String? _loraPath;
  double _loraScale;

  /// The currently loaded model, if any.
  @Deprecated('Use LlamaCppRepository for model management')
  LlamaCppModel? get model => _model;

  /// Whether a model is currently loaded.
  bool get isModelLoaded => _model != null;

  /// Gets the prompt template in use.
  PromptTemplate get template =>
      _template ??
      (_model != null ? getTemplateForModel(_model!.path) : ChatMLTemplate());

  /// Sets the prompt template to use.
  set template(PromptTemplate value) => _template = value;

  // ============================================================
  // LoRA Management (llama.cpp-specific, not in base interface)
  // ============================================================

  /// The current LoRA adapter path, if any.
  String? get loraPath => _loraPath;

  /// The current LoRA scale factor.
  double get loraScale => _loraScale;

  /// Whether a LoRA adapter is configured.
  bool get hasLora => _loraPath != null;

  /// Set a LoRA adapter to use during inference.
  ///
  /// [path] - Path to the LoRA GGUF file.
  /// [scale] - Scale factor (0.0 to 1.0+). Default is 1.0.
  ///
  /// The LoRA will be applied to the context during each inference call.
  /// To switch LoRAs, simply call this method again with a different path.
  ///
  /// Note: This is a llama.cpp-specific feature not available in the base
  /// [LLMChatRepository] interface.
  void setLora(String path, {double scale = 1.0}) {
    _loraPath = path;
    _loraScale = scale;
  }

  /// Set a LoRA adapter from a [LoraConfig].
  void setLoraConfig(LoraConfig config) {
    setLora(config.path, scale: config.scale);
  }

  /// Clear the LoRA adapter.
  ///
  /// After calling this, inference will run without any LoRA applied.
  void clearLora() {
    _loraPath = null;
    _loraScale = 1.0;
  }

  /// Initializes the llama.cpp backend.
  ///
  /// This is called automatically when loading a model, but can be called
  /// explicitly to pre-initialize.
  @Deprecated('Use LlamaCppRepository for backend management')
  void initializeBackend() {
    if (_backendInitialized) return;

    final lib = loadLlamaLibrary();
    _bindings = LlamaBindings(lib);
    
    // Load all backends before initializing
    // This is required for dynamic backend loading (GGML_BACKEND_DL=ON)
    // On Android with GGML_BACKEND_DL=ON, backends are loaded as separate .so files
    final backendsLoaded = BackendInitializer.loadBackends(lib);
    if (!backendsLoaded) {
      _log.warning(
        'Backend loading failed. This may cause model loading to fail on Android with dynamic backend loading enabled.',
      );
    }
    
    _bindings!.llama_backend_init();
    _backendInitialized = true;
  }

  /// Loads a GGUF model from the specified path.
  ///
  /// [modelPath] - Path to the GGUF model file.
  /// [options] - Optional loading options.
  @Deprecated(
    'Use LlamaCppRepository.loadModel() instead for proper separation of concerns',
  )
  Future<void> loadModel(
    String modelPath, {
    ModelLoadOptions options = const ModelLoadOptions(),
  }) async {
    initializeBackend();

    // Unload any existing model
    if (_model != null && _ownsModel) {
      _model!.dispose();
      _model = null;
    }

    _model = LlamaCppModel.load(
      modelPath,
      _bindings!,
      nGpuLayers: options.nGpuLayers,
      useMemoryMap: options.useMemoryMap,
      useMemoryLock: options.useMemoryLock,
      vocabOnly: options.vocabOnly,
    );
  }

  /// Unloads the current model.
  @Deprecated('Use LlamaCppRepository.unloadModel() instead')
  void unloadModel() {
    if (_model != null && _ownsModel) {
      _model!.dispose();
      _model = null;
    }
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
    yield* streamChatWithGenerationOptions(
      model,
      messages: messages,
      think: think,
      tools: tools,
      extra: extra,
      options: options,
      generationOptions: const GenerationOptions(),
    );
  }

  /// Streams a chat response with llama.cpp-specific generation options.
  ///
  /// This is an extension method that allows specifying [GenerationOptions]
  /// for llama.cpp-specific generation parameters (temperature, topP, etc.).
  ///
  /// [generationOptions] - llama.cpp-specific generation parameters.
  Stream<LLMChunk> streamChatWithGenerationOptions(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    StreamChatOptions? options,
    GenerationOptions? generationOptions,
  }) async* {
    final genOptions = generationOptions ?? const GenerationOptions();
    // Validate inputs
    Validation.validateModelName(model);
    Validation.validateMessages(messages);

    // Determine the model path - either from loaded model or lazy loading path
    final String modelPath;
    if (_model != null) {
      modelPath = _model!.path;
    } else if (_modelPath != null) {
      // Lazy loading mode - model will be loaded in the inference isolate
      modelPath = _modelPath!;
    } else {
      throw const ModelLoadException(
        'No model loaded. Call loadModel() first, use LlamaCppChatRepository.withModel(), or use LlamaCppChatRepository.withModelPath().',
      );
    }

    // Validate context size against model limits (only if model is loaded in main isolate)
    if (_model != null && contextSize > _model!.contextSizeTrain) {
      _log.warning(
        'Requested context size ($contextSize) exceeds model training context size (${_model!.contextSizeTrain}). '
        'This may cause issues or be truncated.',
      );
    }

    // Check for images in messages
    final hasImages = messages.any((msg) => msg.images != null && msg.images!.isNotEmpty);
    if (hasImages) {
      // TODO: Full vision support requires additional multimodal bindings
      // For now, throw an informative error
      throw VisionNotSupportedException(
        model,
        'Vision/image support is not yet fully implemented in llm_llamacpp. '
        'Vision models can be loaded and used for text inference, but image input processing requires additional multimodal bindings.',
      );
    }

    // Merge options with individual parameters (options take precedence)
    final effectiveTools = options?.tools.isNotEmpty == true
        ? options!.tools
        : tools;
    final effectiveExtra = options?.extra ?? extra;
    final effectiveToolAttempts = options?.toolAttempts;

    final currentAttempts = effectiveToolAttempts ?? maxToolAttempts;

    _log.fine(
      'streamChat called with ${effectiveTools.length} tools, attempt ${maxToolAttempts - currentAttempts + 1}',
    );
    _log.fine('Messages count: ${messages.length}');
    if (_log.isLoggable(LLMLogLevel.fine)) {
      for (final msg in messages) {
        _log.fine(
          '  - ${msg.role.name}: ${msg.content?.substring(0, msg.content!.length.clamp(0, 100))}...',
        );
      }
    }

    // Format messages using the template
    final prompt = template.format(messages);
    _log.fine('Generated prompt (${prompt.length} chars)');
    if (_log.isLoggable(LLMLogLevel.fine)) {
      _log.fine('--- PROMPT START ---\n$prompt\n--- PROMPT END ---');
    }

    // Use the persistent inference isolate (follows fllama's pattern)
    // This avoids re-initializing the library in each isolate which causes crashes on Android
    final inferenceStream = PersistentInferenceIsolate.instance.runInference(
      modelPath: modelPath,
      prompt: prompt,
      stopTokens: template.stopTokens,
      contextSize: contextSize,
      batchSize: batchSize,
      threads: threads,
      nGpuLayers: nGpuLayers,
      options: genOptions,
      loraPath: _loraPath,
      loraScale: _loraScale,
    );

    try {
      final streamHandler = ToolCallStreamHandler(
        logger: _log,
        tools: effectiveTools,
      );

      await for (final message in inferenceStream) {
        if (message is InferenceToken) {
          final result = streamHandler.processToken(message.token);
          if (result.shouldYield && result.content != null) {
            yield LLMChunk(
              model: model,
              createdAt: DateTime.now(),
              message: LLMChunkMessage(
                content: result.content,
                role: LLMRole.assistant,
              ),
              done: false,
            );
          }
        } else if (message is InferenceComplete) {
          _log.fine(
            'Inference complete. Accumulated content (${streamHandler.accumulatedContent.length} chars)',
          );
          if (_log.isLoggable(LLMLogLevel.fine)) {
            _log.fine(
              '--- RESPONSE START ---\n${streamHandler.accumulatedContent}\n--- RESPONSE END ---',
            );
          }

          // Yield any remaining buffered content
          final remainingContent = streamHandler.finalize(
            hasTools: effectiveTools.isNotEmpty,
          );
          if (remainingContent != null) {
            yield LLMChunk(
              model: model,
              createdAt: DateTime.now(),
              message: LLMChunkMessage(
                content: remainingContent,
                role: LLMRole.assistant,
              ),
              done: false,
            );
          }

          final collectedToolCalls = streamHandler.collectedToolCalls;

          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: null,
              role: LLMRole.assistant,
              toolCalls: collectedToolCalls.isEmpty ? null : collectedToolCalls,
            ),
            done: true,
            promptEvalCount: message.promptTokens,
            evalCount: message.generatedTokens,
          );

          // Handle tool calls if any
          if (collectedToolCalls.isNotEmpty && effectiveTools.isNotEmpty) {
            _log.info('Executing ${collectedToolCalls.length} tool calls...');
            if (currentAttempts > 0) {
              final workingMessages = List<LLMMessage>.from(messages);

              // Add assistant message with tool calls
              workingMessages.add(
                LLMMessage(
                  role: LLMRole.assistant,
                  content: streamHandler.accumulatedContent,
                ),
              );

              // Execute tools and add responses
              final toolMessages = await ToolExecutor.executeTools(
                collectedToolCalls,
                effectiveTools,
                effectiveExtra,
                _log,
              );
              workingMessages.addAll(toolMessages);

              _log.fine('Continuing conversation with tool results...');
              // Continue conversation with tool results
              final nextOptions =
                  options?.copyWith(toolAttempts: currentAttempts - 1) ??
                  StreamChatOptions(
                    tools: effectiveTools,
                    extra: effectiveExtra,
                    toolAttempts: currentAttempts - 1,
                  );
              yield* streamChatWithGenerationOptions(
                model,
                messages: workingMessages,
                tools: effectiveTools,
                extra: effectiveExtra,
                options: nextOptions,
                generationOptions: genOptions,
              );
            } else {
              _log.warning('Max tool attempts reached, not continuing');
            }
          }

          break;
        } else if (message is InferenceError) {
          _log.severe('Inference error: ${message.error}');
          throw InferenceErrorTranslator.translateInferenceError(
            message.error,
            modelPath: _model?.path,
            prompt: prompt,
            contextSize: contextSize,
            batchSize: batchSize,
          );
        }
      }
    } finally {
      // No cleanup needed - persistent isolate stays alive
    }
  }


  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    if (_model == null) {
      throw const ModelLoadException(
        'No model loaded. Call loadModel() first or use LlamaCppChatRepository.withModel().',
      );
    }

    // Validate inputs
    if (messages.isEmpty) {
      throw const LLMApiException(
        'Messages list cannot be empty',
        statusCode: 400,
      );
    }

    // Create a receive port to get embeddings from the isolate
    final receivePort = ReceivePort();

    // Start embedding extraction in an isolate
    Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        runEmbedding,
        EmbeddingRequest(
          sendPort: receivePort.sendPort,
          modelPath: _model!.path,
          messages: messages,
          contextSize: contextSize,
          batchSize: batchSize,
          threads: threads,
          nGpuLayers: nGpuLayers,
        ),
      );
    } catch (e) {
      receivePort.close();
      _log.severe('Failed to spawn embedding isolate: $e');
      throw InferenceException(
        message: 'Failed to spawn embedding isolate: $e',
        details: 'Model: ${_model?.path ?? "unknown"}',
      );
    }

    try {
      final results = <LLMEmbedding>[];
      await for (final message in receivePort) {
        if (message is EmbeddingResult) {
          results.add(message.embedding);
        } else if (message is EmbeddingError) {
          throw InferenceErrorTranslator.translateEmbeddingError(
            message.error,
            modelPath: _model?.path,
            contextSize: contextSize,
            batchSize: batchSize,
          );
        } else if (message is EmbeddingComplete) {
          break;
        }
      }

      return results;
    } finally {
      receivePort.close();
      isolate.kill();
    }
  }

  /// Releases all resources.
  ///
  /// If using [LlamaCppChatRepository.withModel], only chat-specific resources
  /// are released. The model should be unloaded via [LlamaCppRepository].
  void dispose() {
    if (_ownsModel) {
      // ignore: deprecated_member_use_from_same_package
      unloadModel();
      if (_backendInitialized && _bindings != null) {
        _bindings!.llama_backend_free();
        _backendInitialized = false;
      }
    }
    // Clear references but don't dispose if we don't own the model
    _model = null;
    _bindings = null;
  }
}
