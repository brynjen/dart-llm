# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
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
