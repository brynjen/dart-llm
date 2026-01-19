import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llm_core/llm_core.dart';

import 'bindings/llama_bindings.dart';
import 'llamacpp_model.dart';
import 'llamacpp_repository.dart';
import 'loader/loader.dart';
import 'prompt_template.dart';

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
  /// Creates a chat repository with default settings.
  ///
  /// Use [loadModel] to load a model before calling [streamChat].
  /// For proper separation of concerns, prefer using [LlamaCppChatRepository.withModel]
  /// and managing models through [LlamaCppRepository].
  LlamaCppChatRepository({
    this.contextSize = 4096,
    this.batchSize = 512,
    this.threads,
    this.nGpuLayers = 0,
    this.maxToolAttempts = 25,
    PromptTemplate? template,
  }) : _template = template,
       _ownsModel = true;

  /// Creates a chat repository with an already-loaded model.
  ///
  /// This is the preferred constructor when using [LlamaCppRepository] for
  /// model management, as it maintains proper separation of concerns.
  ///
  /// [model] - A model loaded via [LlamaCppRepository.loadModel].
  /// [bindings] - The bindings from [LlamaCppRepository.bindings].
  LlamaCppChatRepository.withModel(
    LlamaCppModel model,
    LlamaBindings bindings, {
    this.contextSize = 4096,
    this.batchSize = 512,
    this.threads,
    this.nGpuLayers = 0,
    this.maxToolAttempts = 25,
    PromptTemplate? template,
  }) : _template = template,
       _model = model,
       _bindings = bindings,
       _backendInitialized = true,
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

  /// The currently loaded model, if any.
  @Deprecated('Use LlamaCppRepository for model management')
  LlamaCppModel? get model => _model;

  /// Whether a model is currently loaded.
  bool get isModelLoaded => _model != null;

  /// Gets the prompt template in use.
  PromptTemplate get template => _template ?? (_model != null ? getTemplateForModel(_model!.path) : ChatMLTemplate());

  /// Sets the prompt template to use.
  set template(PromptTemplate value) => _template = value;

  /// Initializes the llama.cpp backend.
  ///
  /// This is called automatically when loading a model, but can be called
  /// explicitly to pre-initialize.
  @Deprecated('Use LlamaCppRepository for backend management')
  void initializeBackend() {
    if (_backendInitialized) return;

    final lib = loadLlamaLibrary();
    _bindings = LlamaBindings(lib);
    _bindings!.llama_backend_init();
    _backendInitialized = true;
  }

  /// Loads a GGUF model from the specified path.
  ///
  /// [modelPath] - Path to the GGUF model file.
  /// [options] - Optional loading options.
  @Deprecated('Use LlamaCppRepository.loadModel() instead for proper separation of concerns')
  Future<void> loadModel(String modelPath, {ModelLoadOptions options = const ModelLoadOptions()}) async {
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
    List<LLMTool> tools = const [],
    dynamic extra,
    int? toolAttempts,
    bool think = false,
  }) async* {
    if (_model == null) {
      throw ModelLoadException('No model loaded. Call loadModel() first or use LlamaCppChatRepository.withModel().');
    }

    final currentAttempts = toolAttempts ?? maxToolAttempts;
    print('[LlamaCpp] streamChat called with ${tools.length} tools, attempt ${maxToolAttempts - currentAttempts + 1}');
    print('[LlamaCpp] Messages count: ${messages.length}');
    for (final msg in messages) {
      print('[LlamaCpp]   - ${msg.role.name}: ${msg.content?.substring(0, msg.content!.length.clamp(0, 100))}...');
    }

    // Format messages using the template
    final prompt = template.format(messages);
    print('[LlamaCpp] Generated prompt (${prompt.length} chars):');
    print('[LlamaCpp] --- PROMPT START ---');
    print(prompt);
    print('[LlamaCpp] --- PROMPT END ---');

    // Create a receive port to get tokens from the isolate
    final receivePort = ReceivePort();

    // Start inference in an isolate
    final isolate = await Isolate.spawn(
      _runInference,
      _InferenceRequest(
        sendPort: receivePort.sendPort,
        modelPath: _model!.path,
        prompt: prompt,
        stopTokens: template.stopTokens,
        contextSize: contextSize,
        batchSize: batchSize,
        threads: threads,
        nGpuLayers: nGpuLayers,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        maxTokens: 2048,
      ),
    );

    try {
      String accumulatedContent = '';
      List<LLMToolCall> collectedToolCalls = [];
      // Buffer for detecting tool calls mid-stream
      String pendingContent = '';
      bool inPotentialToolCall = false;

      await for (final message in receivePort) {
        if (message is _InferenceToken) {
          accumulatedContent += message.token;
          pendingContent += message.token;

          // Check if we might be in a tool call
          // Look for opening brace that might start a tool call JSON
          if (!inPotentialToolCall && pendingContent.contains('{')) {
            inPotentialToolCall = true;
            print('[LlamaCpp] Detected potential tool call start');
          }

          // If we're in a potential tool call, buffer the content
          if (inPotentialToolCall) {
            // Check if we have a complete JSON object
            final braceCount = _countBraces(pendingContent);
            if (braceCount == 0 && pendingContent.contains('}')) {
              // Potential complete JSON - try to parse
              print('[LlamaCpp] Potential complete JSON, trying to parse: $pendingContent');
              final toolCalls = _parseToolCalls(pendingContent);
              if (toolCalls.isNotEmpty) {
                print('[LlamaCpp] Found ${toolCalls.length} tool calls in buffered content!');
                collectedToolCalls.addAll(toolCalls);
                // Don't yield the tool call JSON to the user
                pendingContent = '';
                inPotentialToolCall = false;
                continue;
              } else {
                // Not a valid tool call, yield the buffered content
                print('[LlamaCpp] Not a valid tool call, yielding buffered content');
                yield LLMChunk(
                  model: model,
                  createdAt: DateTime.now(),
                  message: LLMChunkMessage(content: pendingContent, role: LLMRole.assistant),
                  done: false,
                );
                pendingContent = '';
                inPotentialToolCall = false;
              }
            }
            // Keep buffering if braces aren't balanced
            continue;
          }

          // Normal token - yield immediately
          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(content: message.token, role: LLMRole.assistant),
            done: false,
          );
          pendingContent = '';
        } else if (message is _InferenceComplete) {
          print('[LlamaCpp] Inference complete. Accumulated content (${accumulatedContent.length} chars):');
          print('[LlamaCpp] --- RESPONSE START ---');
          print(accumulatedContent);
          print('[LlamaCpp] --- RESPONSE END ---');

          // Yield any remaining buffered content
          if (pendingContent.isNotEmpty) {
            print('[LlamaCpp] Yielding remaining buffered content: $pendingContent');
            yield LLMChunk(
              model: model,
              createdAt: DateTime.now(),
              message: LLMChunkMessage(content: pendingContent, role: LLMRole.assistant),
              done: false,
            );
          }

          // Check for tool calls in the full response if none found during streaming
          if (tools.isNotEmpty && collectedToolCalls.isEmpty) {
            print('[LlamaCpp] Parsing tool calls from full response...');
            final parsedToolCalls = _parseToolCalls(accumulatedContent);
            print('[LlamaCpp] Found ${parsedToolCalls.length} tool calls');
            for (final tc in parsedToolCalls) {
              print('[LlamaCpp]   - Tool: ${tc.name}, Args: ${tc.arguments}');
            }
            if (parsedToolCalls.isNotEmpty) {
              collectedToolCalls.addAll(parsedToolCalls);
            }
          }

          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(content: null, role: LLMRole.assistant, toolCalls: collectedToolCalls.isEmpty ? null : collectedToolCalls),
            done: true,
            promptEvalCount: message.promptTokens,
            evalCount: message.generatedTokens,
          );

          // Handle tool calls if any
          if (collectedToolCalls.isNotEmpty && tools.isNotEmpty) {
            print('[LlamaCpp] Executing ${collectedToolCalls.length} tool calls...');
            if (currentAttempts > 0) {
              final workingMessages = List<LLMMessage>.from(messages);

              // Add assistant message with tool calls
              workingMessages.add(LLMMessage(role: LLMRole.assistant, content: accumulatedContent));

              // Execute tools and add responses
              for (final toolCall in collectedToolCalls) {
                print('[LlamaCpp] Executing tool: ${toolCall.name}');
                final tool = tools.firstWhere(
                  (t) => t.name == toolCall.name,
                  orElse: () {
                    print('[LlamaCpp] ERROR: Tool ${toolCall.name} not found!');
                    throw Exception('Tool ${toolCall.name} not found');
                  },
                );

                try {
                  final args = json.decode(toolCall.arguments);
                  print('[LlamaCpp] Tool args: $args');
                  final toolResponse = await tool.execute(args, extra: extra) ?? 'Tool ${toolCall.name} returned null';
                  print('[LlamaCpp] Tool response: $toolResponse');

                  workingMessages.add(LLMMessage(role: LLMRole.tool, content: toolResponse.toString(), toolCallId: toolCall.id));
                } catch (e) {
                  print('[LlamaCpp] Tool execution error: $e');
                  workingMessages.add(LLMMessage(role: LLMRole.tool, content: 'Error executing tool: $e', toolCallId: toolCall.id));
                }
              }

              print('[LlamaCpp] Continuing conversation with tool results...');
              // Continue conversation with tool results
              yield* streamChat(model, messages: workingMessages, tools: tools, extra: extra, toolAttempts: currentAttempts - 1);
            } else {
              print('[LlamaCpp] Max tool attempts reached, not continuing');
            }
          }

          break;
        } else if (message is _InferenceError) {
          print('[LlamaCpp] ERROR: ${message.error}');
          throw Exception('Inference error: ${message.error}');
        }
      }
    } finally {
      receivePort.close();
      isolate.kill();
    }
  }

  /// Count unbalanced braces in a string
  int _countBraces(String s) {
    int count = 0;
    for (final c in s.codeUnits) {
      if (c == 123) count++; // {
      if (c == 125) count--; // }
    }
    return count;
  }

  /// Parses tool calls from model output.
  ///
  /// This looks for JSON-formatted tool calls in the response.
  List<LLMToolCall> _parseToolCalls(String content) {
    final toolCalls = <LLMToolCall>[];
    print('[LlamaCpp] _parseToolCalls input: $content');

    // Try to find and parse any JSON object that looks like a tool call
    // First, try to find complete JSON objects
    final jsonObjects = _extractJsonObjects(content);
    print('[LlamaCpp] Found ${jsonObjects.length} JSON objects');

    for (final jsonStr in jsonObjects) {
      print('[LlamaCpp] Trying to parse JSON: $jsonStr');
      try {
        final data = json.decode(jsonStr) as Map<String, dynamic>;

        // Check if it's a tool call format
        if (data.containsKey('name')) {
          String? name;
          String? arguments;

          // Format 1: {"name": "tool", "arguments": {...}}
          if (data.containsKey('arguments')) {
            name = data['name'] as String;
            final args = data['arguments'];
            arguments = args is String ? args : json.encode(args);
          }
          // Format 2: {"name": "tool", "parameters": {...}}
          else if (data.containsKey('parameters')) {
            name = data['name'] as String;
            final args = data['parameters'];
            arguments = args is String ? args : json.encode(args);
          }
          // Format 3: {"name": "tool", "operation": "...", "a": ..., "b": ...}
          // All other keys are arguments
          else {
            name = data['name'] as String;
            final args = Map<String, dynamic>.from(data)..remove('name');
            arguments = json.encode(args);
          }

          print('[LlamaCpp] Parsed tool call: name=$name, args=$arguments');
          toolCalls.add(LLMToolCall(id: 'call_${toolCalls.length}', name: name, arguments: arguments));
        }
      } catch (e) {
        print('[LlamaCpp] Failed to parse JSON: $e');
      }
    }

    // Try XML-like format: <tool_call>...</tool_call>
    final xmlPattern = RegExp(r'<tool_call>\s*(\{.*?\})\s*</tool_call>', multiLine: true, dotAll: true);

    for (final match in xmlPattern.allMatches(content)) {
      try {
        final jsonStr = match.group(1)!;
        print('[LlamaCpp] Found XML-style tool call: $jsonStr');
        final data = json.decode(jsonStr) as Map<String, dynamic>;

        toolCalls.add(
          LLMToolCall(id: 'call_${toolCalls.length}', name: data['name'] as String, arguments: json.encode(data['arguments'] ?? data['parameters'] ?? {})),
        );
      } catch (e) {
        print('[LlamaCpp] Failed to parse XML-style tool call: $e');
      }
    }

    // Try function call format: calculator({"operation": "multiply", ...})
    final funcPattern = RegExp(r'(\w+)\s*\(\s*(\{[^}]+\})\s*\)', multiLine: true);

    for (final match in funcPattern.allMatches(content)) {
      try {
        final name = match.group(1)!;
        final argsStr = match.group(2)!;
        print('[LlamaCpp] Found function-style call: $name($argsStr)');

        // Verify it's valid JSON
        json.decode(argsStr);

        toolCalls.add(LLMToolCall(id: 'call_${toolCalls.length}', name: name, arguments: argsStr));
      } catch (e) {
        print('[LlamaCpp] Failed to parse function-style call: $e');
      }
    }

    print('[LlamaCpp] Total tool calls found: ${toolCalls.length}');
    return toolCalls;
  }

  /// Extract JSON objects from a string
  List<String> _extractJsonObjects(String content) {
    final objects = <String>[];
    var depth = 0;
    var start = -1;

    for (var i = 0; i < content.length; i++) {
      final c = content[i];
      if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          objects.add(content.substring(start, i + 1));
          start = -1;
        }
      }
    }

    return objects;
  }

  @override
  Future<List<LLMEmbedding>> embed({required String model, required List<String> messages, Map<String, dynamic> options = const {}}) async {
    // Embeddings require a different approach with llama.cpp
    // For now, throw unsupported
    throw UnsupportedError(
      'Embeddings are not yet implemented for llama.cpp backend. '
      'Use a dedicated embedding model or the Ollama/ChatGPT backends.',
    );
  }

  /// Releases all resources.
  ///
  /// If using [LlamaCppChatRepository.withModel], only chat-specific resources
  /// are released. The model should be unloaded via [LlamaCppRepository].
  void dispose() {
    if (_ownsModel) {
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

// Isolate communication messages

class _InferenceRequest {
  _InferenceRequest({
    required this.sendPort,
    required this.modelPath,
    required this.prompt,
    required this.stopTokens,
    required this.contextSize,
    required this.batchSize,
    this.threads,
    required this.nGpuLayers,
    required this.temperature,
    required this.topP,
    required this.topK,
    required this.maxTokens,
  });

  final SendPort sendPort;
  final String modelPath;
  final String prompt;
  final List<String> stopTokens;
  final int contextSize;
  final int batchSize;
  final int? threads;
  final int nGpuLayers;
  final double temperature;
  final double topP;
  final int topK;
  final int maxTokens;
}

class _InferenceToken {
  _InferenceToken(this.token);
  final String token;
}

class _InferenceComplete {
  _InferenceComplete({required this.promptTokens, required this.generatedTokens});
  final int promptTokens;
  final int generatedTokens;
}

class _InferenceError {
  _InferenceError(this.error);
  final String error;
}

/// Runs inference in an isolate.
void _runInference(_InferenceRequest request) {
  try {
    // Initialize llama.cpp in this isolate
    final lib = loadLlamaLibrary();
    final bindings = LlamaBindings(lib);
    bindings.llama_backend_init();

    // Load the model
    final modelParams = bindings.llama_model_default_params();
    modelParams.n_gpu_layers = request.nGpuLayers;

    final modelPathPtr = request.modelPath.toNativeUtf8();
    final model = bindings.llama_load_model_from_file(modelPathPtr.cast(), modelParams);
    calloc.free(modelPathPtr);

    if (model == nullptr) {
      request.sendPort.send(_InferenceError('Failed to load model'));
      return;
    }

    // Get vocab from model for tokenization
    final vocab = bindings.llama_model_get_vocab(model);

    // Create context
    final ctxParams = bindings.llama_context_default_params();
    ctxParams.n_ctx = request.contextSize;
    ctxParams.n_batch = request.batchSize;
    if (request.threads != null) {
      ctxParams.n_threads = request.threads!;
      ctxParams.n_threads_batch = request.threads!;
    }

    final ctx = bindings.llama_new_context_with_model(model, ctxParams);
    if (ctx == nullptr) {
      bindings.llama_free_model(model);
      request.sendPort.send(_InferenceError('Failed to create context'));
      return;
    }

    try {
      // Tokenize prompt using vocab
      final promptPtr = request.prompt.toNativeUtf8();
      final maxTokens = request.prompt.length + 256;
      final tokensPtr = calloc<Int32>(maxTokens);

      final nTokens = bindings.llama_tokenize(
        vocab, // Use vocab instead of model
        promptPtr.cast(),
        request.prompt.length,
        tokensPtr,
        maxTokens,
        true, // add_special
        true, // parse_special
      );
      calloc.free(promptPtr);

      if (nTokens < 0) {
        calloc.free(tokensPtr);
        request.sendPort.send(_InferenceError('Failed to tokenize prompt'));
        return;
      }

      // Evaluate prompt using batch
      var batch = bindings.llama_batch_get_one(tokensPtr, nTokens);
      if (bindings.llama_decode(ctx, batch) != 0) {
        calloc.free(tokensPtr);
        request.sendPort.send(_InferenceError('Failed to evaluate prompt'));
        return;
      }

      // Set up sampling chain
      final samplerParams = bindings.llama_sampler_chain_default_params();
      final sampler = bindings.llama_sampler_chain_init(samplerParams);

      bindings.llama_sampler_chain_add(sampler, bindings.llama_sampler_init_temp(request.temperature));
      bindings.llama_sampler_chain_add(sampler, bindings.llama_sampler_init_top_k(request.topK));
      bindings.llama_sampler_chain_add(sampler, bindings.llama_sampler_init_top_p(request.topP, 1));
      bindings.llama_sampler_chain_add(
        sampler,
        bindings.llama_sampler_init_dist(42), // seed
      );

      // Generate tokens
      const bufferSize = 256;
      final pieceBuffer = calloc<Char>(bufferSize);
      var generatedTokens = 0;
      final newTokenPtr = calloc<Int32>(1);

      while (generatedTokens < request.maxTokens) {
        // Sample next token
        final newToken = bindings.llama_sampler_sample(sampler, ctx, -1);

        // Check for end of generation using vocab
        if (bindings.llama_vocab_is_eog(vocab, newToken)) {
          break;
        }

        // Convert token to text using vocab
        final pieceLen = bindings.llama_token_to_piece(
          vocab, // Use vocab instead of model
          newToken,
          pieceBuffer,
          bufferSize,
          0, // lstrip
          true, // special
        );

        if (pieceLen > 0) {
          final piece = pieceBuffer.cast<Utf8>().toDartString(length: pieceLen);

          // Check for stop tokens
          bool shouldStop = false;
          for (final stopToken in request.stopTokens) {
            if (piece.contains(stopToken)) {
              shouldStop = true;
              break;
            }
          }

          if (shouldStop) break;

          request.sendPort.send(_InferenceToken(piece));
        }

        // Decode the new token
        newTokenPtr.value = newToken;
        batch = bindings.llama_batch_get_one(newTokenPtr, 1);
        if (bindings.llama_decode(ctx, batch) != 0) {
          break;
        }

        generatedTokens++;
      }

      // Cleanup sampling
      bindings.llama_sampler_free(sampler);
      calloc.free(pieceBuffer);
      calloc.free(newTokenPtr);
      calloc.free(tokensPtr);

      request.sendPort.send(_InferenceComplete(promptTokens: nTokens, generatedTokens: generatedTokens));
    } finally {
      bindings.llama_free(ctx);
      bindings.llama_free_model(model);
      bindings.llama_backend_free();
    }
  } catch (e) {
    request.sendPort.send(_InferenceError(e.toString()));
  }
}
