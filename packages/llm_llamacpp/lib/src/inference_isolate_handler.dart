part of 'persistent_inference_isolate.dart';

void _handleInferenceRequest(
  _InferenceRequestMessage request,
  SendPort mainSendPort,
  ffi.DynamicLibrary lib,
  LlamaBindings bindings,
) {
  ffi.Pointer<llama_adapter_lora>? loraAdapter;

  try {
    final modelParams = bindings.llama_model_default_params();
    modelParams.n_gpu_layers = request.nGpuLayers;

    final modelPathPtr = request.modelPath.toNativeUtf8();
    final model = bindings.llama_load_model_from_file(
      modelPathPtr.cast(),
      modelParams,
    );
    calloc.free(modelPathPtr);

    if (model.address == 0) {
      mainSendPort.send(
        _IsolateResponse(
          requestId: request.requestId,
          payload: InferenceError(
            'Failed to load model from ${request.modelPath}',
          ),
          isComplete: true,
        ),
      );
      return;
    }

    if (request.loraPath != null) {
      final loraPathPtr = request.loraPath!.toNativeUtf8();
      loraAdapter = bindings.llama_adapter_lora_init(model, loraPathPtr.cast());
      calloc.free(loraPathPtr);

      if (loraAdapter.address == 0) {
        bindings.llama_free_model(model);
        mainSendPort.send(
          _IsolateResponse(
            requestId: request.requestId,
            payload: InferenceError('Failed to load LoRA adapter'),
            isComplete: true,
          ),
        );
        return;
      }
    }

    final vocab = bindings.llama_model_get_vocab(model);

    // Log vocab/special-token diagnostics so we can quickly see whether the
    // tokenizer is auto-prepending BOS, what BOS/EOS ids are, etc. These
    // numbers are essential when the formatted chat prompt does not produce
    // coherent output (a sign the chat template / special-token plumbing is
    // mismatched against this particular model).
    try {
      final bosId = bindings.llama_vocab_bos(vocab);
      final eosId = bindings.llama_vocab_eos(vocab);
      final eotId = bindings.llama_vocab_eot(vocab);
      final addBos = bindings.llama_vocab_get_add_bos(vocab);
      final addEos = bindings.llama_vocab_get_add_eos(vocab);
      final nTokensInVocab = bindings.llama_vocab_n_tokens(vocab);
      // ignore: avoid_print
      print(
        '[inference_isolate_handler] Vocab: nTokens=$nTokensInVocab '
        'bos=$bosId eos=$eosId eot=$eotId '
        'add_bos_token=$addBos add_eos_token=$addEos',
      );
    } catch (e) {
      // ignore: avoid_print
      print(
        '[inference_isolate_handler] Could not query vocab diagnostics: $e',
      );
    }

    final ctxParams = bindings.llama_context_default_params();
    ctxParams.n_ctx = request.contextSize;
    ctxParams.n_batch = request.batchSize;
    if (request.threads != null) {
      ctxParams.n_threads = request.threads!;
      ctxParams.n_threads_batch = request.threads!;
    }

    final ctx = bindings.llama_new_context_with_model(model, ctxParams);
    if (ctx.address == 0) {
      if (loraAdapter != null) {
        bindings.llama_adapter_lora_free(loraAdapter);
      }
      bindings.llama_free_model(model);
      mainSendPort.send(
        _IsolateResponse(
          requestId: request.requestId,
          payload: InferenceError('Failed to create context'),
          isComplete: true,
        ),
      );
      return;
    }

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
        mainSendPort.send(
          _IsolateResponse(
            requestId: request.requestId,
            payload: InferenceError('Failed to apply LoRA adapter'),
            isComplete: true,
          ),
        );
        return;
      }
    }

    try {
      String prompt;
      // Inspect the model's GGUF chat template so we can correctly compensate
      // for cases where llama_chat_apply_template's hard-coded fallback drops
      // the leading BOS that the real Jinja template would emit.
      String? modelTemplateStr;
      final templatePtr = bindings.llama_model_chat_template(
        model,
        ffi.nullptr,
      );
      if (templatePtr.address != 0) {
        try {
          modelTemplateStr = templatePtr.cast<Utf8>().toDartString();
        } catch (_) {
          modelTemplateStr = null;
        }
      }

      if (request.messages != null && request.messages!.isNotEmpty) {
        prompt = _applyNativeChatTemplate(bindings, model, request.messages!);
      } else {
        prompt = request.prompt;
      }

      // llama_chat_apply_template is NOT a Jinja interpreter; if the model's
      // GGUF template starts with `{{- bos_token -}}` (LFM2.5, some Llama 3
      // variants, etc.), the fallback chatml formatter drops the BOS. The
      // tokenizer's `add_bos_token` flag is also frequently false on such
      // models, because the template is supposed to handle BOS itself. Net
      // result: no BOS token in the prompt → model behaves like a base model
      // and never produces an EOS. Detect this and prepend the BOS id by hand.
      final usingChatTemplate =
          request.messages != null && request.messages!.isNotEmpty;
      final addBosByTokenizer = bindings.llama_vocab_get_add_bos(vocab);
      final templateRefersToBos =
          modelTemplateStr != null &&
          (modelTemplateStr.contains('bos_token') ||
              modelTemplateStr.contains('<|begin_of_text|>') ||
              modelTemplateStr.contains('<|startoftext|>'));
      final shouldManuallyPrependBos =
          usingChatTemplate && templateRefersToBos && !addBosByTokenizer;
      // ignore: avoid_print
      print(
        '[inference_isolate_handler] BOS handling: '
        'add_bos_token=$addBosByTokenizer '
        'template_refers_to_bos=$templateRefersToBos '
        'manual_bos_prepend=$shouldManuallyPrependBos',
      );

      final promptPtr = prompt.toNativeUtf8();
      // Use UTF-8 byte length, not Dart string length (UTF-16 code units), so
      // that prompts with non-ASCII characters tokenize correctly.
      final promptByteLen = promptPtr.length;
      final maxTokens = promptByteLen + 256;
      final tokensPtr = calloc<ffi.Int32>(maxTokens);

      // When we'll manually prepend BOS, ask the tokenizer NOT to add specials.
      // Otherwise keep the prior behavior so the tokenizer's configured
      // BOS/EOS handling stays in effect.
      final tokenizerAddSpecial = !shouldManuallyPrependBos;
      final nTokensFromTokenizer = bindings.llama_tokenize(
        vocab,
        promptPtr.cast(),
        promptByteLen,
        tokensPtr,
        maxTokens,
        tokenizerAddSpecial,
        true,
      );
      calloc.free(promptPtr);

      if (nTokensFromTokenizer < 0) {
        calloc.free(tokensPtr);
        // ignore: avoid_print
        print(
          '[inference_isolate_handler] Tokenization failed '
          '(returned $nTokensFromTokenizer) '
          'for prompt of ${prompt.length} chars / $promptByteLen bytes',
        );
        mainSendPort.send(
          _IsolateResponse(
            requestId: request.requestId,
            payload: InferenceError('Failed to tokenize prompt'),
            isComplete: true,
          ),
        );
        return;
      }

      var nTokens = nTokensFromTokenizer;
      if (shouldManuallyPrependBos) {
        final bosId = bindings.llama_vocab_bos(vocab);
        if (bosId >= 0) {
          // Shift right by 1 to make room for BOS at index 0.
          for (var i = nTokens; i > 0; i--) {
            tokensPtr[i] = tokensPtr[i - 1];
          }
          tokensPtr[0] = bosId;
          nTokens += 1;
          // ignore: avoid_print
          print(
            '[inference_isolate_handler] Manually prepended BOS token id=$bosId; '
            'prompt now $nTokens tokens',
          );
        } else {
          // ignore: avoid_print
          print(
            '[inference_isolate_handler] WARNING: wanted to prepend BOS but '
            'llama_vocab_bos returned $bosId',
          );
        }
      }

      // ignore: avoid_print
      print(
        '[inference_isolate_handler] Tokenized prompt: $nTokens tokens '
        '(${prompt.length} chars, contextSize=${request.contextSize})',
      );

      // Decode the first few tokens so we can see whether ChatML markers like
      // `<|im_start|>` are tokenizing as single special tokens or being split
      // into many literal-character tokens. The latter is a strong sign that
      // the model's vocab does not contain those markers and the chat
      // template we used is wrong for this model.
      try {
        final previewCount = nTokens < 15 ? nTokens : 15;
        final pieceBuf = calloc<ffi.Char>(64);
        final preview = StringBuffer();
        try {
          for (var i = 0; i < previewCount; i++) {
            final id = tokensPtr[i];
            final pieceLen = bindings.llama_token_to_piece(
              vocab,
              id,
              pieceBuf,
              64,
              0,
              true,
            );
            String text;
            if (pieceLen <= 0) {
              text = '?';
            } else {
              text = pieceBuf
                  .cast<Utf8>()
                  .toDartString(length: pieceLen)
                  .replaceAll('\n', r'\n')
                  .replaceAll('\r', r'\r');
            }
            preview.write('  [$i] id=$id "$text"\n');
          }
        } finally {
          calloc.free(pieceBuf);
        }
        // ignore: avoid_print
        print(
          '[inference_isolate_handler] First $previewCount token(s):\n$preview',
        );
      } catch (e) {
        // ignore: avoid_print
        print('[inference_isolate_handler] Could not preview tokens: $e');
      }

      final batch = bindings.llama_batch_get_one(tokensPtr, nTokens);
      if (bindings.llama_decode(ctx, batch) != 0) {
        calloc.free(tokensPtr);
        mainSendPort.send(
          _IsolateResponse(
            requestId: request.requestId,
            payload: InferenceError('Failed to evaluate prompt'),
            isComplete: true,
          ),
        );
        return;
      }

      final sampler = _configureSampler(bindings, request.options);

      // Many models use ChatML-style turn boundaries (`<|im_end|>`) but ship
      // GGUFs where llama_vocab_is_eog only flags the model-level EOS token.
      // When the chat template renders to `<|im_start|>...<|im_end|>` we add
      // `<|im_end|>` as an explicit stop string so generation actually stops
      // at the end of the assistant turn instead of running to maxTokens.
      final effectiveStopTokens = <String>[...request.stopTokens];
      if (prompt.contains('<|im_end|>') || prompt.contains('<|im_start|>')) {
        if (!effectiveStopTokens.contains('<|im_end|>')) {
          effectiveStopTokens.add('<|im_end|>');
          // ignore: avoid_print
          print(
            '[inference_isolate_handler] Auto-added "<|im_end|>" to stop tokens '
            '(ChatML-style template detected).',
          );
        }
      }
      // Same idea for Llama-3-style end-of-turn markers.
      if (prompt.contains('<|eot_id|>')) {
        if (!effectiveStopTokens.contains('<|eot_id|>')) {
          effectiveStopTokens.add('<|eot_id|>');
        }
      }

      final generatedTokens = _generateTokens(
        bindings,
        model,
        ctx,
        sampler,
        vocab,
        request.options,
        effectiveStopTokens,
        request.requestId,
        mainSendPort,
      );

      bindings.llama_sampler_free(sampler);
      calloc.free(tokensPtr);

      mainSendPort.send(
        _IsolateResponse(
          requestId: request.requestId,
          payload: InferenceComplete(
            promptTokens: nTokens,
            generatedTokens: generatedTokens,
          ),
          isComplete: true,
        ),
      );
    } finally {
      if (loraAdapter != null) {
        bindings.llama_clear_adapter_lora(ctx);
        bindings.llama_adapter_lora_free(loraAdapter);
      }
      bindings.llama_free(ctx);
      bindings.llama_free_model(model);
    }
  } catch (e) {
    mainSendPort.send(
      _IsolateResponse(
        requestId: request.requestId,
        payload: InferenceError(e.toString()),
        isComplete: true,
      ),
    );
  }
}
