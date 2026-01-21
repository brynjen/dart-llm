import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llm_llamacpp/src/backend_initializer.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/generation_options.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';

/// Manages a persistent inference isolate for running LLM inference.
///
/// This follows the pattern used by fllama: a single persistent isolate
/// handles all inference requests, avoiding the issues caused by
/// re-initializing the library in multiple isolates.
///
/// The isolate is lazily initialized on first use and stays alive for the
/// lifetime of the application. This is important because:
/// 1. Native library state (backends) is shared across the process
/// 2. Re-loading libraries in separate isolates causes FFI issues on Android
/// 3. A persistent isolate avoids the overhead of spawning new isolates
class PersistentInferenceIsolate {
  PersistentInferenceIsolate._();

  static final PersistentInferenceIsolate _instance =
      PersistentInferenceIsolate._();
  static PersistentInferenceIsolate get instance => _instance;

  SendPort? _helperSendPort;
  Isolate? _helperIsolate;
  ReceivePort? _mainReceivePort;
  bool _initializing = false;

  /// Mapping from request IDs to response controllers
  final Map<int, StreamController<dynamic>> _pendingRequests = {};
  int _nextRequestId = 0;

  /// Initialize the persistent isolate if not already running.
  Future<void> _ensureInitialized() async {
    if (_helperSendPort != null) return;
    if (_initializing) {
      // Wait for initialization to complete
      while (_helperSendPort == null) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return;
    }

    _initializing = true;
    try {
      final completer = Completer<SendPort>();
      _mainReceivePort = ReceivePort();

      _mainReceivePort!.listen((message) {
        if (message is SendPort) {
          completer.complete(message);
          return;
        }

        // Handle responses from the helper isolate
        if (message is _IsolateResponse) {
          final controller = _pendingRequests[message.requestId];
          if (controller != null) {
            controller.add(message.payload);
            if (message.isComplete) {
              controller.close();
              _pendingRequests.remove(message.requestId);
            }
          }
        }
      });

      // ignore: avoid_print
      print('[PersistentInferenceIsolate] Spawning helper isolate...');
      _helperIsolate = await Isolate.spawn(
        _isolateMain,
        _mainReceivePort!.sendPort,
      );

      _helperSendPort = await completer.future;
      // ignore: avoid_print
      print('[PersistentInferenceIsolate] Helper isolate ready');
    } finally {
      _initializing = false;
    }
  }

  /// Run inference and return a stream of responses.
  Stream<dynamic> runInference({
    required String modelPath,
    required String prompt,
    required List<String> stopTokens,
    required int contextSize,
    required int batchSize,
    required int nGpuLayers,
    required GenerationOptions options,
    int? threads,
    String? loraPath,
    double loraScale = 1.0,
  }) async* {
    await _ensureInitialized();

    final requestId = _nextRequestId++;
    final controller = StreamController<dynamic>();
    _pendingRequests[requestId] = controller;

    // Send the request to the helper isolate
    _helperSendPort!.send(_InferenceRequestMessage(
      requestId: requestId,
      modelPath: modelPath,
      prompt: prompt,
      stopTokens: stopTokens,
      contextSize: contextSize,
      batchSize: batchSize,
      nGpuLayers: nGpuLayers,
      options: options,
      threads: threads,
      loraPath: loraPath,
      loraScale: loraScale,
    ));

    yield* controller.stream;
  }

  /// Shutdown the persistent isolate.
  void dispose() {
    _helperIsolate?.kill();
    _helperIsolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _helperSendPort = null;
    for (final controller in _pendingRequests.values) {
      controller.close();
    }
    _pendingRequests.clear();
  }
}

/// The main entry point for the helper isolate.
void _isolateMain(SendPort mainSendPort) {
  // ignore: avoid_print
  print('[InferenceHelperIsolate] Starting...');

  // Initialize the library in this isolate
  // Since the main isolate no longer calls any llama.cpp functions (using withModelPath),
  // we need to do FULL initialization here including loading all backends.
  late final ffi.DynamicLibrary lib;
  late final LlamaBindings bindings;

  try {
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Initializing backend (full initialization)...');
    // Use full initialization since main isolate does NO FFI calls
    final result = BackendInitializer.initializeBackend();
    lib = result.$1;
    bindings = result.$2;
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Backend initialized successfully');
  } catch (e) {
    // ignore: avoid_print
    print('[InferenceHelperIsolate] ERROR initializing backend: $e');
    return;
  }

  // Create receive port for requests from main isolate
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is _InferenceRequestMessage) {
      _handleInferenceRequest(message, mainSendPort, lib, bindings);
    }
  });

  // ignore: avoid_print
  print('[InferenceHelperIsolate] Ready to accept requests');
}

/// Handle an inference request in the helper isolate.
void _handleInferenceRequest(
  _InferenceRequestMessage request,
  SendPort mainSendPort,
  ffi.DynamicLibrary lib,
  LlamaBindings bindings,
) {
  ffi.Pointer<llama_adapter_lora>? loraAdapter;

  try {
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Processing request ${request.requestId}');
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Loading model from: ${request.modelPath}');

    // Load the model
    final modelParams = bindings.llama_model_default_params();
    modelParams.n_gpu_layers = request.nGpuLayers;

    final modelPathPtr = request.modelPath.toNativeUtf8();
    final model = bindings.llama_load_model_from_file(
      modelPathPtr.cast(),
      modelParams,
    );
    calloc.free(modelPathPtr);
    
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Model loaded, address: ${model.address}');

    if (model.address == 0) {
      // ignore: avoid_print
      print('[InferenceHelperIsolate] ERROR: Model address is 0 (failed to load)');
      mainSendPort.send(_IsolateResponse(
        requestId: request.requestId,
        payload: InferenceError('Failed to load model from ${request.modelPath}'),
        isComplete: true,
      ));
      return;
    }

    // Load LoRA adapter if specified
    if (request.loraPath != null) {
      // ignore: avoid_print
      print('[InferenceHelperIsolate] Loading LoRA adapter...');
      final loraPathPtr = request.loraPath!.toNativeUtf8();
      loraAdapter = bindings.llama_adapter_lora_init(model, loraPathPtr.cast());
      calloc.free(loraPathPtr);

      if (loraAdapter.address == 0) {
        bindings.llama_free_model(model);
        mainSendPort.send(_IsolateResponse(
          requestId: request.requestId,
          payload: InferenceError('Failed to load LoRA adapter'),
          isComplete: true,
        ));
        return;
      }
    }

    // Get vocab from model for tokenization
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Getting vocab...');
    final vocab = bindings.llama_model_get_vocab(model);
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Vocab address: ${vocab.address}');

    // Create context  
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Getting default context params...');
    final ctxParams = bindings.llama_context_default_params();
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Setting context params...');
    ctxParams.n_ctx = request.contextSize;
    ctxParams.n_batch = request.batchSize;
    if (request.threads != null) {
      ctxParams.n_threads = request.threads!;
      ctxParams.n_threads_batch = request.threads!;
    }

    // ignore: avoid_print
    print('[InferenceHelperIsolate] Creating context with model...');
    final ctx = bindings.llama_new_context_with_model(model, ctxParams);
    if (ctx.address == 0) {
      if (loraAdapter != null) {
        bindings.llama_adapter_lora_free(loraAdapter);
      }
      bindings.llama_free_model(model);
      mainSendPort.send(_IsolateResponse(
        requestId: request.requestId,
        payload: InferenceError('Failed to create context'),
        isComplete: true,
      ));
      return;
    }

    // Apply LoRA adapter to context if loaded
    if (loraAdapter != null) {
      final result = bindings.llama_set_adapter_lora(
        ctx,
        loraAdapter,
        request.loraScale,
      );
      if (result != 0) {
        bindings.llama_free(ctx);
        bindings.llama_adapter_lora_free(loraAdapter);
        bindings.llama_free_model(model);
        mainSendPort.send(_IsolateResponse(
          requestId: request.requestId,
          payload: InferenceError('Failed to apply LoRA adapter'),
          isComplete: true,
        ));
        return;
      }
    }

    try {
      // Tokenize prompt
      final promptPtr = request.prompt.toNativeUtf8();
      final maxTokens = request.prompt.length + 256;
      final tokensPtr = calloc<ffi.Int32>(maxTokens);

      final nTokens = bindings.llama_tokenize(
        vocab,
        promptPtr.cast(),
        request.prompt.length,
        tokensPtr,
        maxTokens,
        true,
        true,
      );
      calloc.free(promptPtr);

      if (nTokens < 0) {
        calloc.free(tokensPtr);
        mainSendPort.send(_IsolateResponse(
          requestId: request.requestId,
          payload: InferenceError('Failed to tokenize prompt'),
          isComplete: true,
        ));
        return;
      }

      // Evaluate prompt
      var batch = bindings.llama_batch_get_one(tokensPtr, nTokens);
      if (bindings.llama_decode(ctx, batch) != 0) {
        calloc.free(tokensPtr);
        mainSendPort.send(_IsolateResponse(
          requestId: request.requestId,
          payload: InferenceError('Failed to evaluate prompt'),
          isComplete: true,
        ));
        return;
      }

      // Set up sampling
      final samplerParams = bindings.llama_sampler_chain_default_params();
      final sampler = bindings.llama_sampler_chain_init(samplerParams);

      bindings.llama_sampler_chain_add(
        sampler,
        bindings.llama_sampler_init_temp(request.options.temperature),
      );
      bindings.llama_sampler_chain_add(
        sampler,
        bindings.llama_sampler_init_top_k(request.options.topK),
      );
      bindings.llama_sampler_chain_add(
        sampler,
        bindings.llama_sampler_init_top_p(request.options.topP, 1),
      );

      // Add penalties if specified
      if (request.options.repeatPenalty != null ||
          request.options.frequencyPenalty != null ||
          request.options.presencePenalty != null) {
        final repeatPenalty = request.options.repeatPenalty ?? 1.0;
        final freqPenalty = request.options.frequencyPenalty != null
            ? (request.options.frequencyPenalty! < 0
                ? 1.0 + request.options.frequencyPenalty!.abs()
                : 1.0 - request.options.frequencyPenalty!)
            : 0.0;
        final presencePenalty = request.options.presencePenalty != null
            ? (request.options.presencePenalty! < 0
                ? 1.0 + request.options.presencePenalty!.abs()
                : 1.0 - request.options.presencePenalty!)
            : 0.0;

        bindings.llama_sampler_chain_add(
          sampler,
          bindings.llama_sampler_init_penalties(
            64,
            repeatPenalty,
            freqPenalty,
            presencePenalty,
          ),
        );
      }

      // Use provided seed or generate random one
      final seed =
          request.options.seed ?? DateTime.now().microsecondsSinceEpoch;
      bindings.llama_sampler_chain_add(
        sampler,
        bindings.llama_sampler_init_dist(seed),
      );

      // Generate tokens
      const bufferSize = 256;
      var pieceBuffer = calloc<ffi.Char>(bufferSize);
      var generatedTokens = 0;
      final newTokenPtr = calloc<ffi.Int32>(1);

      while (generatedTokens < request.options.maxTokens) {
        final newToken = bindings.llama_sampler_sample(sampler, ctx, -1);

        if (bindings.llama_vocab_is_eog(vocab, newToken)) {
          break;
        }

        var pieceLen = bindings.llama_token_to_piece(
          vocab,
          newToken,
          pieceBuffer,
          bufferSize,
          0,
          true,
        );

        if (pieceLen < 0) {
          final requiredSize = -pieceLen;
          calloc.free(pieceBuffer);
          pieceBuffer = calloc<ffi.Char>(requiredSize);
          pieceLen = bindings.llama_token_to_piece(
            vocab,
            newToken,
            pieceBuffer,
            requiredSize,
            0,
            true,
          );
        }

        if (pieceLen > 0) {
          final piece =
              pieceBuffer.cast<Utf8>().toDartString(length: pieceLen);

          // Check for stop tokens
          bool shouldStop = false;
          for (final stopToken in request.stopTokens) {
            if (piece.contains(stopToken)) {
              shouldStop = true;
              break;
            }
          }

          if (shouldStop) break;

          // Send token to main isolate
          mainSendPort.send(_IsolateResponse(
            requestId: request.requestId,
            payload: InferenceToken(piece),
            isComplete: false,
          ));
        }

        // Decode the new token
        newTokenPtr[0] = newToken;
        batch = bindings.llama_batch_get_one(newTokenPtr, 1);
        if (bindings.llama_decode(ctx, batch) != 0) {
          break;
        }

        generatedTokens++;
      }

      // Cleanup
      bindings.llama_sampler_free(sampler);
      calloc.free(pieceBuffer);
      calloc.free(newTokenPtr);
      calloc.free(tokensPtr);

      // Send completion
      mainSendPort.send(_IsolateResponse(
        requestId: request.requestId,
        payload: InferenceComplete(
          promptTokens: nTokens,
          generatedTokens: generatedTokens,
        ),
        isComplete: true,
      ));
    } finally {
      if (loraAdapter != null) {
        bindings.llama_clear_adapter_lora(ctx);
        bindings.llama_adapter_lora_free(loraAdapter);
      }
      bindings.llama_free(ctx);
      bindings.llama_free_model(model);
    }
  } catch (e) {
    mainSendPort.send(_IsolateResponse(
      requestId: request.requestId,
      payload: InferenceError(e.toString()),
      isComplete: true,
    ));
  }
}

/// Internal message for inference requests sent to the helper isolate.
class _InferenceRequestMessage {
  _InferenceRequestMessage({
    required this.requestId,
    required this.modelPath,
    required this.prompt,
    required this.stopTokens,
    required this.contextSize,
    required this.batchSize,
    required this.nGpuLayers,
    required this.options,
    this.threads,
    this.loraPath,
    this.loraScale = 1.0,
  });

  final int requestId;
  final String modelPath;
  final String prompt;
  final List<String> stopTokens;
  final int contextSize;
  final int batchSize;
  final int? threads;
  final int nGpuLayers;
  final GenerationOptions options;
  final String? loraPath;
  final double loraScale;
}

/// Internal response wrapper for sending data back from the helper isolate.
class _IsolateResponse {
  _IsolateResponse({
    required this.requestId,
    required this.payload,
    required this.isComplete,
  });

  final int requestId;
  final dynamic payload;
  final bool isComplete;
}
