/// Helpers for driving llama.cpp's context-level LoRA API.
///
/// Upstream replaced the incremental `llama_set_adapter_lora` /
/// `llama_rm_adapter_lora` / `llama_clear_adapter_lora` trio with a single
/// declarative `llama_set_adapters_lora`, which replaces a context's entire
/// adapter set on every call and takes parallel C arrays. These helpers wrap
/// the array marshalling so callers that only ever deal with a single adapter
/// don't each reimplement it.
///
/// `LoraManager` tracks multi-adapter state per context; use that instead when
/// adapters need to be added and removed independently.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';

/// Applies exactly [adapter] at [scale] to [ctx], replacing any adapters
/// already set on the context.
///
/// Returns 0 on success, negative on error.
int setSingleContextLoraAdapter(
  LlamaBindings bindings,
  Pointer<llama_context> ctx,
  Pointer<llama_adapter_lora> adapter,
  double scale,
) {
  final adapters = calloc<Pointer<llama_adapter_lora>>();
  final scales = calloc<Float>();
  try {
    adapters[0] = adapter;
    scales[0] = scale;
    return bindings.llama_set_adapters_lora(ctx, adapters, 1, scales);
  } finally {
    calloc.free(adapters);
    calloc.free(scales);
  }
}

/// Removes all LoRA adapters from [ctx].
///
/// Returns 0 on success, negative on error.
int clearContextLoraAdapters(
  LlamaBindings bindings,
  Pointer<llama_context> ctx,
) => bindings.llama_set_adapters_lora(ctx, nullptr, 0, nullptr);
