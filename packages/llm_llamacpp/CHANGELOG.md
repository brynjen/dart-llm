# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Model-aware tool calling. Tool definitions are now advertised to the model in the format its family was trained on, and tool calls are parsed back out of the raw token stream. Covers LFM2/LFM2.5 (Pythonic calls inside `<|tool_call_start|>`), Hermes/Qwen (`<tool_call>` tags), Mistral (`[TOOL_CALLS]`), Llama 3.x (`<|python_tag|>`), bare Pythonic call lists, and bare JSON. See `lib/src/tool_calls/tool_call_syntax.dart` to add a family.
- The example app's `CalculatorTool` no longer echoes integral operands as floats. It widens everything to `double` for the arithmetic, and used to report `347.0 × 89.0 = 30883` — handing a small model a decimal-looking operand next to an integer-looking answer, which invited it to restate the result with invented separators (`3,088,83`). It now prints `347 × 89 = 30883`. The trailing-zero trim is also confined to the fractional part; applied to a whole integer it would have turned `10200` into `102`.
- The example app renders each tool call as a subdued "thinking" bubble showing the call and, once it has run, its result — so the model's reasoning steps are visible instead of hidden. Because llm_llamacpp executes tools internally and does not surface results in the chunk stream, the example's `CalculatorTool` takes an `onInvoke` callback to report what it did.
- The tool-call family is resolved from the GGUF chat template, falling back to probing the tokenizer vocabulary for the family's opening delimiter. The vocabulary probe is what makes LFM2.5 work: `LFM2.5-1.2B-Instruct-Q4_K_M.gguf` ships a trimmed 1783-character template that renders tool *definitions* but has no `render_tool_calls` macro and no reference to `tool_calls` at all, so it never emits the call delimiters (the 5487-character template in the base model repo does). The model still emits `<|tool_call_start|>` because that behaviour is in the weights, and the token is in its vocabulary.

### Fixed
- Tool calling stopped working after the first turn of a conversation. Verified with `tool/tool_call_probe.dart`: 1/3 turns used the tool before, 3/3 after. A caller that replays only the visible assistant text builds a history in which the assistant announces a tool and then answers without calling one — the model copies that and stops calling tools. `LLMChunkMessage.rawContent` now carries the turn as the model emitted it (tool-call markup intact) so callers can replay the sequence Liquid AI documents: system(tools) -> user -> assistant(with call) -> tool(result) -> assistant. The example app was updated to do so, including the `toolCallId` that `llm_core` validation requires on a tool message.
- The example app's history window was a blind tail slice, which could begin inside a tool exchange and produce a `tool` turn with no assistant call before it. It now snaps to a user message.
- `LlamaCppChatRepository` accepted `tools` but never told the model they existed, so callers had to hand-write tool syntax into the system prompt — which then fought the model's own trained format. The package now injects the tool list itself, mirroring `injectResponseFormat`.
- Tool calls no longer leak into user-visible text. The stream handler only buffered on `{`, so an LFM2 call was streamed to the UI verbatim as `<|tool_call_start|>[...]`. It now buffers on any known opening delimiter and holds back partial delimiters, so a delimiter split across tokens never emits a fragment.
- A single `<tool_call>{...}</tool_call>` yielded the same call twice: the parser ran a JSON pass, an XML pass and a function-style pass over the whole output. Parsing is now delimiter-first and deduplicated.
- The JSON object scanner is string-aware, so braces inside a string argument no longer unbalance it.
- The default HTTP client is now `createLLMHttpClient()`, which applies `TimeoutConfig.connectionTimeout` and bounds the connection pool.
- `hook/build.dart` now declares the FFI bindings as a hook dependency (`output.dependencies`). Without it the hooks runner reused its cached output, so regenerating the bindings never recomputed the ABI fingerprint — silently defeating the prebuilt-invalidation scheme it exists to drive.
- Prebuilt bundles are cached under `outputDirectoryShared` instead of the per-config `outputDirectory`, so a bundle is downloaded once rather than once per target OS/architecture.
- CMake configuration disables `LLAMA_BUILD_APP`, `LLAMA_BUILD_COMMON` and `LLAMA_BUILD_UI`. Upstream's new unified `app` target is not gated behind `LLAMA_BUILD_COMMON` and broke the source build on generated headers it never received.
- `ffigen.yaml` no longer carries a hardcoded absolute include path from another machine; `compiler-opts` is now package-relative.

### Changed
- Native-assets toolchain migrated off 1.x: `hooks ^2.0.0`, `code_assets ^1.2.1`, `ffigen ^21.0.0`. The hooks 2.0 break (`ProtocolExtension` becoming a base class) only affects asset-type packages, so the build hook needed no API changes.
- `llamacpp` submodule updated to current upstream, the vendored `src/include/` headers re-synced from it, and the FFI bindings regenerated with ffigen 21. The vendored headers had drifted *ahead* of the pinned submodule, so the bindings described an ABI newer than the library actually built. Removed the third, stale `src/llama.h` copy.
- Migrated off deprecated llama.cpp entry points (`llama_load_model_from_file`, `llama_free_model`, `llama_new_context_with_model`, `llama_n_vocab`, `llama_token_bos`/`_eos`/`_nl`/`_pad`, and the `llama_n_*` model getters) to their modern equivalents.
- `LoraManager` is reimplemented on upstream's declarative `llama_set_adapters_lora`, which replaced the incremental `llama_set_adapter_lora`/`llama_rm_adapter_lora`/`llama_clear_adapter_lora` calls. `applyLora`, `removeLora`, `clearLoras` and `switchLora` keep their signatures and behavior; the manager now tracks the applied set per context and re-sends it after each change. Added `activeLoras(ctx)` and `forgetContext(ctx)` — call the latter before freeing a context, since contexts are tracked by pointer address and llama.cpp can reuse a freed address.
- `ModelLoadOptions.useMemoryMap` / `useMemoryLock` are unchanged, but now map onto upstream's new `load_mode` enum, which replaced the `use_mmap`/`use_direct_io`/`use_mlock` booleans.
- Dependency floors raised: Dart SDK `^3.12.0` (was `^3.8.0`), `http ^1.6.0`; dev deps refreshed (`lints ^6.1.0`, `test ^1.31.0`) and new lint findings fixed (null-aware elements, private named initializing formals). Flutter floor raised to `>=3.44.0` to match the Dart floor.


## [0.3.0] - 2026-08-17

### Changed
- Version alignment with `llm_core` 0.3.0 (`ReasoningEffort` available through
  the re-export); no functional changes.

## [0.2.0] - 2026-08-12

### Changed
- **Breaking:** Adopted `LLMChatOptions?` in chat APIs.
- Explicit empty tool lists now clear inherited tool options.
- Local tool loops now respect `autoExecuteTools: false`.

### Added
- Structured output support via `StreamChatOptions.responseFormat`:
  - `JsonFormat()` — injects a "respond with valid JSON only" instruction into the system message
  - `JsonSchemaFormat(name, schema)` — injects the JSON Schema into the system message
  - If no system message exists, one is prepended; otherwise the instruction is appended to the existing system message
  - `responseFormat` is propagated through tool-call loops so format constraints are preserved across all turns
- `injectResponseFormat(messages, format)` package-private helper function; unit-testable standalone
- Bumped `llm_core` dependency to `^0.2.0`

### Fixed
- Android hosted-package builds now rely on the native-assets hook instead of Gradle invoking repository-local build scripts, and the Android native asset bundle includes the required llama.cpp runtime `.so` dependencies.

## [0.1.9] - 2026-02-28

### Changed
- `maxToolAttempts` default increased from 25 to 90
- Bumped `llm_core` dependency to ^0.1.9

## [0.1.8] - 2026-02-26

### Changed
- Bumped `llm_core` dependency to ^0.1.8 for tool calling stream visibility

## [0.1.7] - 2026-02-10

### Added
- `batchEmbed()` implementation: delegates to existing `embed()` (processes multiple messages in the embedding isolate).

## [0.1.6] - 2026-02-10

### Fixed
- Confirmed that parsed tool calls from llama.cpp outputs always include non-null, non-empty `LLMToolCall.id` values across supported formats (JSON, XML-style, and function-style), maintaining compatibility with `llm_core` tool-calling expectations.
- Added tests for `ToolCallParser` to verify that tool call IDs are populated correctly for downstream `toolCallId` usage.

## [0.1.5] - 2026-01-26

### Added
- Support for `StreamChatOptions` in `streamChat()` method
- Support for `chatResponse()` method for non-streaming complete responses
- Input validation for model names and messages
- Improved isolate-based inference handling

### Changed
- `streamChat()` now accepts optional `StreamChatOptions` parameter
- Improved error handling
- Enhanced documentation

## [0.1.0] - 2026-01-19

### Added
- Initial release
- Local on-device inference with GGUF models via llama.cpp
- Cross-platform support: Android, iOS, macOS, Windows, Linux
- Streaming token generation with isolate-based inference
- Multiple prompt templates: ChatML, Llama2, Llama3, Alpaca, Vicuna, Phi-3
- Tool calling support via prompt convention
- GPU acceleration support (CUDA, Metal, Vulkan)
- Model management features:
  - Model discovery in directories
  - Model loading with pooling (reference counting)
  - GGUF metadata reading without loading
  - HuggingFace model downloading
  - Safetensors to GGUF conversion
- Native Assets build hook for automatic binary management
- Prebuilt binaries available via GitHub Releases
