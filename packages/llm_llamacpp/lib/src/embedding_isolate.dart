import 'dart:ffi' as ffi;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:llm_core/llm_core.dart' show LLMEmbedding;
import 'package:llm_llamacpp/src/backend_initializer.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';

/// Runs embedding extraction in an isolate.
///
/// This function is spawned in a separate isolate to extract embeddings
/// without blocking the main isolate. It handles model loading,
/// tokenization, pooling, and normalization.
void runEmbedding(EmbeddingRequest request) {
  try {
    // Initialize llama.cpp in this isolate
    // Use initializeBackendForIsolate() which skips backend loading
    // since backends are already loaded in native memory by the main isolate
    final (lib, bindings) = BackendInitializer.initializeBackendForIsolate();

    // Load the model
    final modelParams = bindings.llama_model_default_params();
    modelParams.n_gpu_layers = request.nGpuLayers;

    final modelPathPtr = request.modelPath.toNativeUtf8();
    final model = bindings.llama_load_model_from_file(
      modelPathPtr.cast(),
      modelParams,
    );
    calloc.free(modelPathPtr);

    if (model.address == 0) {
      request.sendPort.send(EmbeddingError('Failed to load model'));
      return;
    }

    // Get embedding dimension
    final nEmb = bindings.llama_model_n_embd(model);

    // Create context
    final ctxParams = bindings.llama_context_default_params();
    ctxParams.n_ctx = request.contextSize;
    ctxParams.n_batch = request.batchSize;
    if (request.threads != null) {
      ctxParams.n_threads = request.threads!;
      ctxParams.n_threads_batch = request.threads!;
    }

    final ctx = bindings.llama_new_context_with_model(model, ctxParams);
    if (ctx.address == 0) {
      bindings.llama_free_model(model);
      request.sendPort.send(EmbeddingError('Failed to create context'));
      return;
    }

    try {
      // Get vocab from model for tokenization
      final vocab = bindings.llama_model_get_vocab(model);
      final poolingType = bindings.llama_pooling_type$1(ctx);

      // Process each message
      for (final message in request.messages) {
        // Tokenize message
        final messagePtr = message.toNativeUtf8();
        final maxTokens = message.length + 256;
        final tokensPtr = calloc<ffi.Int32>(maxTokens);

        final nTokens = bindings.llama_tokenize(
          vocab,
          messagePtr.cast(),
          message.length,
          tokensPtr,
          maxTokens,
          true, // add_special
          true, // parse_special
        );
        calloc.free(messagePtr);

        if (nTokens < 0) {
          calloc.free(tokensPtr);
          request.sendPort.send(EmbeddingError('Failed to tokenize message'));
          continue;
        }

        // Clear KV cache (irrelevant for embeddings)
        bindings.llama_memory_clear(bindings.llama_get_memory(ctx), true);

        // Create batch and decode
        final batch = bindings.llama_batch_get_one(tokensPtr, nTokens);
        if (bindings.llama_decode(ctx, batch) != 0) {
          calloc.free(tokensPtr);
          request.sendPort.send(EmbeddingError('Failed to decode message'));
          continue;
        }

        // Get embeddings based on pooling type
        ffi.Pointer<ffi.Float>? embdPtr;
        if (poolingType.value == 0) {
          // LLAMA_POOLING_TYPE_NONE - use token embeddings
          // For simplicity, use the last token's embedding
          embdPtr = bindings.llama_get_embeddings_ith(ctx, -1);
        } else {
          // Use sequence embedding (pooled)
          embdPtr = bindings.llama_get_embeddings_seq(ctx, 0);
        }

        if (embdPtr.address == 0) {
          calloc.free(tokensPtr);
          request.sendPort.send(EmbeddingError('Failed to get embeddings'));
          continue;
        }

        // Copy embedding to Dart list
        final embedding = embdPtr
            .asTypedList(nEmb)
            .map((f) => f.toDouble())
            .toList();

        // Normalize embedding (L2 normalization)
        final norm = math.sqrt(
          embedding.map((e) => e * e).reduce((a, b) => a + b),
        );
        if (norm > 0) {
          for (int i = 0; i < embedding.length; i++) {
            embedding[i] = embedding[i] / norm;
          }
        }

        // Send embedding result
        request.sendPort.send(
          EmbeddingResult(
            LLMEmbedding(
              model: request.modelPath,
              embedding: embedding,
              promptEvalCount: nTokens,
            ),
          ),
        );

        calloc.free(tokensPtr);
      }

      request.sendPort.send(EmbeddingComplete());
    } finally {
      bindings.llama_free(ctx);
      bindings.llama_free_model(model);
      bindings.llama_backend_free();
    }
  } catch (e) {
    request.sendPort.send(EmbeddingError(e.toString()));
  }
}
