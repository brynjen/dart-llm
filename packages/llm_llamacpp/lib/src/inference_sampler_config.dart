part of 'persistent_inference_isolate.dart';

/// Configures the sampler chain for text generation.
ffi.Pointer<llama_sampler> _configureSampler(
  LlamaBindings bindings,
  GenerationOptions options,
) {
  final samplerParams = bindings.llama_sampler_chain_default_params();
  final sampler = bindings.llama_sampler_chain_init(samplerParams);

  bindings.llama_sampler_chain_add(
    sampler,
    bindings.llama_sampler_init_temp(options.temperature),
  );
  bindings.llama_sampler_chain_add(
    sampler,
    bindings.llama_sampler_init_top_k(options.topK),
  );
  bindings.llama_sampler_chain_add(
    sampler,
    bindings.llama_sampler_init_top_p(options.topP, 1),
  );

  if (options.repeatPenalty != null ||
      options.frequencyPenalty != null ||
      options.presencePenalty != null) {
    final repeatPenalty = options.repeatPenalty ?? 1.0;
    final freqPenalty = options.frequencyPenalty != null
        ? (options.frequencyPenalty! < 0
              ? 1.0 + options.frequencyPenalty!.abs()
              : 1.0 - options.frequencyPenalty!)
        : 0.0;
    final presencePenalty = options.presencePenalty != null
        ? (options.presencePenalty! < 0
              ? 1.0 + options.presencePenalty!.abs()
              : 1.0 - options.presencePenalty!)
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

  final seed = options.seed ?? DateTime.now().microsecondsSinceEpoch;
  bindings.llama_sampler_chain_add(
    sampler,
    bindings.llama_sampler_init_dist(seed),
  );

  return sampler;
}
