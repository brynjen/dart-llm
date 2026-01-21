import 'dart:ffi' as ffi;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:llm_llamacpp/src/backend_initializer.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';

/// Runs inference in an isolate.
///
/// This function is spawned in a separate isolate to perform inference
/// without blocking the main isolate. It handles model loading, LoRA
/// application, tokenization, sampling, and token generation.
void runInference(InferenceRequest request) {
  ffi.Pointer<llama_adapter_lora>? loraAdapter;

  try {
    // Initialize llama.cpp in this isolate
    // Use initializeBackendForIsolate() which skips backend loading
    // since backends are already loaded in native memory by the main isolate
    // ignore: avoid_print
    print('[inference_isolate] Starting initialization...');
    final (lib, bindings) = BackendInitializer.initializeBackendForIsolate();
    // ignore: avoid_print
    print('[inference_isolate] Backend initialized');

    // Load the model
    // ignore: avoid_print
    print('[inference_isolate] Getting model params...');
    final modelParams = bindings.llama_model_default_params();
    modelParams.n_gpu_layers = request.nGpuLayers;
    // ignore: avoid_print
    print('[inference_isolate] n_gpu_layers: ${request.nGpuLayers}');

    // ignore: avoid_print
    print('[inference_isolate] Loading model from: ${request.modelPath}');
    final modelPathPtr = request.modelPath.toNativeUtf8();
    final model = bindings.llama_load_model_from_file(
      modelPathPtr.cast(),
      modelParams,
    );
    calloc.free(modelPathPtr);
    // ignore: avoid_print
    print('[inference_isolate] Model loaded, address: ${model.address}');

    if (model.address == 0) {
      request.sendPort.send(InferenceError('Failed to load model'));
      return;
    }

    // Load LoRA adapter if specified
    if (request.loraPath != null) {
      // ignore: avoid_print
      print('[inference_isolate] Loading LoRA adapter...');
      final loraPathPtr = request.loraPath!.toNativeUtf8();
      loraAdapter = bindings.llama_adapter_lora_init(model, loraPathPtr.cast());
      calloc.free(loraPathPtr);

      if (loraAdapter.address == 0) {
        bindings.llama_free_model(model);
        request.sendPort.send(
          InferenceError('Failed to load LoRA adapter: ${request.loraPath}'),
        );
        return;
      }
    }

    // Get vocab from model for tokenization
    // ignore: avoid_print
    print('[inference_isolate] Getting vocab...');
    final vocab = bindings.llama_model_get_vocab(model);
    // ignore: avoid_print
    print('[inference_isolate] Vocab address: ${vocab.address}');

    // Create context
    // ignore: avoid_print
    print('[inference_isolate] Creating context params...');
    final ctxParams = bindings.llama_context_default_params();
    ctxParams.n_ctx = request.contextSize;
    ctxParams.n_batch = request.batchSize;
    if (request.threads != null) {
      ctxParams.n_threads = request.threads!;
      ctxParams.n_threads_batch = request.threads!;
    }
    // ignore: avoid_print
    print('[inference_isolate] n_ctx: ${request.contextSize}, n_batch: ${request.batchSize}');

    // ignore: avoid_print
    print('[inference_isolate] Creating context...');
    final ctx = bindings.llama_new_context_with_model(model, ctxParams);
    // ignore: avoid_print
    print('[inference_isolate] Context created, address: ${ctx.address}');
    
    if (ctx.address == 0) {
      if (loraAdapter != null) {
        bindings.llama_adapter_lora_free(loraAdapter);
      }
      bindings.llama_free_model(model);
      final errorMsg =
          'Failed to create context (contextSize: ${request.contextSize}, batchSize: ${request.batchSize})';
      request.sendPort.send(InferenceError(errorMsg));
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
        request.sendPort.send(InferenceError('Failed to apply LoRA adapter'));
        return;
      }
    }

    try {
      // Tokenize prompt using vocab
      final promptPtr = request.prompt.toNativeUtf8();
      final maxTokens = request.prompt.length + 256;
      final tokensPtr = calloc<ffi.Int32>(maxTokens);

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
        final errorMsg = nTokens == -1
            ? 'Failed to tokenize prompt: buffer too small'
            : 'Failed to tokenize prompt: error code $nTokens';
        request.sendPort.send(InferenceError(errorMsg));
        return;
      }

      // Evaluate prompt using batch
      var batch = bindings.llama_batch_get_one(tokensPtr, nTokens);
      if (bindings.llama_decode(ctx, batch) != 0) {
        calloc.free(tokensPtr);
        request.sendPort.send(InferenceError('Failed to evaluate prompt'));
        return;
      }

      // Set up sampling chain
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
        // Use default penalty_last_n of 64 if not specified
        // Convert frequency/presence penalties: OpenAI uses -2.0 to 2.0, llama.cpp uses 0.0+
        // For frequency: positive values increase likelihood, negative decrease
        // For presence: positive values increase likelihood of new tokens
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
            64, // penalty_last_n: look at last 64 tokens
            repeatPenalty,
            freqPenalty,
            presencePenalty,
          ),
        );
      }

      // Use provided seed or generate random one
      final seed = request.options.seed ?? math.Random().nextInt(0x7FFFFFFF);
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
        // Sample next token
        final newToken = bindings.llama_sampler_sample(sampler, ctx, -1);

        // Check for end of generation using vocab
        if (bindings.llama_vocab_is_eog(vocab, newToken)) {
          break;
        }

        // Convert token to text using vocab
        // First, try with the current buffer size
        var pieceLen = bindings.llama_token_to_piece(
          vocab, // Use vocab instead of model
          newToken,
          pieceBuffer,
          bufferSize,
          0, // lstrip
          true, // special
        );

        // If buffer was too small (negative return), query the actual size needed
        if (pieceLen < 0) {
          // Query the actual size needed (negative value indicates required size)
          final requiredSize = -pieceLen;
          // Free old buffer and allocate larger one
          calloc.free(pieceBuffer);
          pieceBuffer = calloc<ffi.Char>(requiredSize);

          // Try again with the correct size
          pieceLen = bindings.llama_token_to_piece(
            vocab,
            newToken,
            pieceBuffer,
            requiredSize,
            0, // lstrip
            true, // special
          );
        }

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

          request.sendPort.send(InferenceToken(piece));
        }

        // Decode the new token
        newTokenPtr[0] = newToken;
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

      request.sendPort.send(
        InferenceComplete(
          promptTokens: nTokens,
          generatedTokens: generatedTokens,
        ),
      );
    } finally {
      // Clear LoRA from context before freeing
      if (loraAdapter != null) {
        bindings.llama_clear_adapter_lora(ctx);
        bindings.llama_adapter_lora_free(loraAdapter);
      }
      bindings.llama_free(ctx);
      bindings.llama_free_model(model);
      bindings.llama_backend_free();
    }
  } catch (e) {
    request.sendPort.send(InferenceError(e.toString()));
  }
}
