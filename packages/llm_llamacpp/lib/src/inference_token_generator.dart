part of 'persistent_inference_isolate.dart';

/// Generates tokens and sends them via the send port.
///
/// Returns the number of generated tokens.
int _generateTokens(
  LlamaBindings bindings,
  ffi.Pointer<llama_model> model,
  ffi.Pointer<llama_context> ctx,
  ffi.Pointer<llama_sampler> sampler,
  ffi.Pointer<llama_vocab> vocab,
  GenerationOptions options,
  List<String> stopTokens,
  int requestId,
  SendPort mainSendPort,
) {
  const bufferSize = 256;
  var pieceBuffer = calloc<ffi.Char>(bufferSize);
  var generatedTokens = 0;
  var stopped = false;
  final tokenDecoder = StreamingUtf8Decoder();
  final newTokenPtr = calloc<ffi.Int32>(1);

  var stoppedOnEog = false;
  // Cap the per-token diagnostic so we don't flood adb logcat. The first 32
  // generated tokens are usually enough to diagnose template / sampler issues.
  const debugTokenLimit = 32;
  // Buffer for decoding individual tokens for the debug print.
  final debugPieceBuf = calloc<ffi.Char>(64);

  while (generatedTokens < options.maxTokens) {
    final newToken = bindings.llama_sampler_sample(sampler, ctx, -1);

    final isEog = bindings.llama_vocab_is_eog(vocab, newToken);
    if (generatedTokens < debugTokenLimit) {
      final pieceLen = bindings.llama_token_to_piece(
        vocab,
        newToken,
        debugPieceBuf,
        64,
        0,
        true,
      );
      String text;
      if (pieceLen <= 0) {
        text = '?';
      } else {
        try {
          text = debugPieceBuf
              .cast<Utf8>()
              .toDartString(length: pieceLen)
              .replaceAll('\n', r'\n')
              .replaceAll('\r', r'\r');
        } catch (_) {
          text = '<utf8 decode failed>';
        }
      }
      // ignore: avoid_print
      print(
        '[inference_token_generator] gen[$generatedTokens] '
        'id=$newToken eog=$isEog "$text"',
      );
    }

    if (isEog) {
      // ignore: avoid_print
      print(
        '[inference_token_generator] EOG token detected (id=$newToken) '
        'after $generatedTokens generated tokens; stopping generation',
      );
      stoppedOnEog = true;
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
      final piece = tokenDecoder.add(
        pieceBuffer.cast<ffi.Uint8>().asTypedList(pieceLen),
      );

      bool shouldStop = false;
      for (final stopToken in stopTokens) {
        if (piece.contains(stopToken)) {
          shouldStop = true;
          break;
        }
      }

      if (shouldStop) {
        stopped = true;
        break;
      }

      if (piece.isNotEmpty) {
        mainSendPort.send(
          _IsolateResponse(
            requestId: requestId,
            payload: InferenceToken(piece),
            isComplete: false,
          ),
        );
      }
    }

    newTokenPtr[0] = newToken;
    final batch = bindings.llama_batch_get_one(newTokenPtr, 1);
    if (bindings.llama_decode(ctx, batch) != 0) {
      break;
    }

    generatedTokens++;
  }

  final trailingPiece = stopped ? '' : tokenDecoder.close();
  if (trailingPiece.isNotEmpty) {
    mainSendPort.send(
      _IsolateResponse(
        requestId: requestId,
        payload: InferenceToken(trailingPiece),
        isComplete: false,
      ),
    );
  }

  if (!stoppedOnEog && !stopped && generatedTokens >= options.maxTokens) {
    // ignore: avoid_print
    print(
      '[inference_token_generator] WARNING: hit maxTokens (${options.maxTokens}) '
      'without seeing EOG. The model never produced an end-of-generation token. '
      'This usually indicates a chat-template / special-token mismatch.',
    );
  }

  calloc.free(pieceBuffer);
  calloc.free(newTokenPtr);
  calloc.free(debugPieceBuf);

  return generatedTokens;
}
