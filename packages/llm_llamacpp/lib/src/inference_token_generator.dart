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
  final newTokenPtr = calloc<ffi.Int32>(1);

  while (generatedTokens < options.maxTokens) {
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
      final piece = pieceBuffer.cast<Utf8>().toDartString(length: pieceLen);

      bool shouldStop = false;
      for (final stopToken in stopTokens) {
        if (piece.contains(stopToken)) {
          shouldStop = true;
          break;
        }
      }

      if (shouldStop) break;

      mainSendPort.send(
        _IsolateResponse(
          requestId: requestId,
          payload: InferenceToken(piece),
          isComplete: false,
        ),
      );
    }

    newTokenPtr[0] = newToken;
    final batch = bindings.llama_batch_get_one(newTokenPtr, 1);
    if (bindings.llama_decode(ctx, batch) != 0) {
      break;
    }

    generatedTokens++;
  }

  calloc.free(pieceBuffer);
  calloc.free(newTokenPtr);

  return generatedTokens;
}
