# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2026-08-18

### Added
- Model-aware tool calling. Tool definitions are advertised in the format the loaded model's family was trained on, and calls are parsed back out of the raw token stream: LFM2/LFM2.5, Hermes/Qwen, Mistral, Llama 3.x, bare Pythonic and bare JSON. See `lib/src/tool_calls/tool_call_syntax.dart` to add a family.
- The family is resolved from the GGUF chat template, falling back to a tokenizer-vocabulary probe. The probe is what makes LFM2.5 work: its GGUF ships a trimmed template that never emits the call delimiters, but the model emits them anyway.
- The example app renders each tool call as a subdued thinking bubble showing the call and its result.

### Fixed
- Tool calling stopped working after the first turn. Callers must replay `LLMChunkMessage.rawContent` into history so the assistant turn keeps its tool-call markup; the example app now does.
- `LlamaCppChatRepository` accepted `tools` but never told the model they existed. The package injects the tool list itself.
- Tool calls no longer leak into user-visible text as raw delimiters, including when a delimiter is split across tokens.
- A single `<tool_call>{...}</tool_call>` no longer yields the same call twice; parsing is delimiter-first and deduplicated.
- The JSON object scanner is string-aware, so braces inside a string argument no longer unbalance it.
- Desktop builds bundled only `libllama`, not the `ggml` libraries it links against. An app worked on the machine that built it and broke as soon as it moved.
- The macOS Flutter loader opened `libllama.dylib`, which is never in the app bundle. It now opens `@rpath/llama.framework/llama`.
- `hook/build.dart` declares the FFI bindings as a hook dependency, without which regenerated bindings never invalidated the prebuilt cache.
- Prebuilt bundles are cached under `outputDirectoryShared`, so a bundle downloads once rather than once per target.
- CMake configuration disables `LLAMA_BUILD_APP`, `LLAMA_BUILD_COMMON` and `LLAMA_BUILD_UI`; upstream's unified `app` target broke the source build.
- `ffigen.yaml` no longer carries a hardcoded absolute include path from another machine.
- The example app's `CalculatorTool` no longer echoes integral operands as floats, and its history window snaps to a user message instead of slicing into a tool exchange.
- The default HTTP client is now `createLLMHttpClient()`, which applies `TimeoutConfig.connectionTimeout` and bounds the connection pool.

### Changed
- Native-assets toolchain migrated off 1.x: `hooks ^2.0.0`, `code_assets ^1.2.1`, `ffigen ^21.0.0`.
- `llamacpp` submodule updated to current upstream, vendored `src/include/` headers re-synced, FFI bindings regenerated, and the stale third `src/llama.h` copy removed.
- Migrated off deprecated llama.cpp entry points (`llama_load_model_from_file`, `llama_n_vocab`, the `llama_n_*` model getters and friends) to their modern equivalents.
- `LoraManager` reimplemented on upstream's declarative `llama_set_adapters_lora`. `applyLora`, `removeLora`, `clearLoras` and `switchLora` keep their signatures; added `activeLoras(ctx)` and `forgetContext(ctx)` — call the latter before freeing a context.
- `ModelLoadOptions.useMemoryMap` / `useMemoryLock` now map onto upstream's `load_mode` enum.
- Documentation corrected: the prompt-template classes (`ChatMLTemplate` and friends) were removed in 0.1.5. Templates come from the GGUF via `llama_chat_apply_template()`.
- The prebuilt native bundle's version is read from `pubspec.yaml` instead of a hand-maintained constant, and `.github/workflows/build-release.yaml` reads the same field — so bumping the package version is what builds and points at a matching native release. Previously the constant said `0.4.0` while the package was `0.3.0`, and no such release existed.
- Native release tags are bare versions (`0.3.1`) rather than `v`-prefixed. The hook downloads from `releases/download/<version>/`, and the workflow tags accordingly; the legacy `v*` tag form still triggers a build.
- Documentation rewritten for the current build: there is no manual native-library step, no workflow to run by hand, and nothing to copy into `jniLibs`.
- Dependency floors raised: Dart SDK `^3.12.0` (was `^3.8.0`), `http ^1.6.0`, `lints ^6.1.0`, `test ^1.31.0`. Flutter floor raised to `>=3.44.0`.

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
