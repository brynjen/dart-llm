# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2026-08-18

### Added
- **llm_core** — `createLLMHttpClient()` is the default HTTP client for every backend: bounded pool per host, `TimeoutConfig.connectionTimeout` applied, idle connections retired after 3s.
- **llm_core** — `WriteGatedHttpClient` bounds concurrent connect+write phases (4 slots on macOS/iOS) to work around a Dart VM kqueue defect that loses writable events.
- **llm_core** — `LLMChunkMessage.rawContent` carries the assistant turn as the model emitted it, tool-call markup intact.
- **llm_llamacpp** — model-aware tool calling: definitions advertised in the loaded model's own format, calls parsed back out of the raw token stream (LFM2/LFM2.5, Hermes/Qwen, Mistral, Llama 3.x, bare Pythonic, bare JSON).
- **llm_gemini** — an `example/` directory, so all seven packages have one.

### Fixed
- **All backends** — sustained concurrent streaming through one repository periodically stalled and silently recovered on retry. Four defects in the shared HTTP path, all fixed; full investigation in `docs/concurrent-send-stall.md`.
- **All backends, macOS/iOS** — the residual burst stall was root-caused to the Dart VM's macOS kqueue event handler, not to any server. Bounded write admission eliminates it.
- **llm_llamacpp** — tool calling stopped working after the first conversation turn, tool-call markup leaked into user-visible text, and desktop builds shipped `libllama` without the `ggml` libraries it links against.
- **Documentation** — the whole doc set was brought back in line with the code: `llm_vllm` was missing from `llm_core`, `ARCHITECTURE.md` and `SECURITY.md`; `llm_llamacpp` documented a build process and a prompt-template API that no longer exist; `llm_chatgpt` advertised Azure OpenAI support it never had; several snippets did not compile.

### Changed
- **llm_core** — `HttpClientHelper.sendStreamingRequest` applies a timeout to `send()` by default; it previously did not.
- **llm_llamacpp** — native-assets toolchain migrated off 1.x (`hooks ^2.0.0`, `code_assets ^1.2.1`, `ffigen ^21.0.0`), submodule updated to current upstream with bindings regenerated, and `LoraManager` reimplemented on upstream's declarative adapter API.
- **llm_llamacpp** — the prebuilt native bundle's release version now comes from `pubspec.yaml` on both ends (the build hook and `build-release.yaml`), so it cannot drift. `build-release.yaml` also builds on a push to `main` that changes the version or the FFI bindings, skipping the build when the release already carries assets for that ABI fingerprint.
- Dependency floors raised: Dart SDK `^3.12.0` (was `^3.8.0`), `http ^1.6.0`, `lints ^6.1.0`, `test ^1.31.0`, `melos ^7.8.0`; Flutter `>=3.44.0`.
- All packages bumped to `0.3.1`; `llm_core` constraint updated to `^0.3.1` across the backends.

### Removed
- `packages/llm_vllm/_mc.dart`, `_probe.dart` and `_tok.dart` — scratch socket probes that shipped to pub.dev. The equivalent documented harnesses live in `packages/llm_vllm/example/`.
- `scripts/build-android-libs.sh`, `scripts/build-android-docker.sh` and `scripts/Dockerfile.android-build` — superseded by `packages/llm_llamacpp/hook/build.dart`.

## [0.3.0] - 2026-08-17

### Added
- **llm_core** — `ReasoningEffort` enum (`none`…`max`) and `LLMChatOptions.reasoningEffort`, a portable reasoning-depth knob alongside `reasoningBudget`; `LLMUsage.reasoningTokens`.
- **llm_chatgpt** — reasoning-model support: per-model detection, `reasoning_effort` mapping, sampling params dropped where the API rejects them, and streaming usage via `stream_options.include_usage`.
- **llm_claude** — `reasoningEffort` maps to `output_config.effort` on current models and to `budget_tokens` on legacy ones.
- **llm_gemini** — `reasoningEffort` maps to `thinking_level`; thought-token usage surfaced.
- **llm_ollama** — `think` accepts Ollama's level strings (`low`/`medium`/`high`/`max`).

### Fixed
- **llm_gemini** — migrated to the Interactions API's steps-based input format; the old turn-based format is now rejected by the live API. Tool loops echo the model's thought signature.
- **llm_vllm** — correctness sweep over parameter handling, the stream converter, embeddings and the pool. See the package CHANGELOG.

### Changed
- All packages bumped to `0.3.0`; `llm_core` constraint updated to `^0.3.0`.

## [0.2.0] - 2026-08-12

### Added
- **llm_claude** — New Anthropic Claude backend package: streaming chat, tool calling with `tool_choice`, model-aware thinking (adaptive on current models, token budget on older ones), and native structured output via `output_config.format`
- **llm_gemini** — New Google Gemini backend package targeting the **Interactions API** (`POST /v1beta/interactions`; Google labels `generateContent` legacy): streaming chat, tool calling, thinking with thought summaries separated from content, native structured output, and embeddings. The API key is sent as the `x-goog-api-key` header rather than a URL query parameter.
- **Structured output** (`LLMResponseFormat`) across all backends:
  - `JsonFormat` — simple JSON mode
  - `JsonSchemaFormat` — full JSON Schema enforcement (native where supported, system-message injection otherwise)
  - `responseFormat` field added to `StreamChatOptions` (fully backward compatible)
  - ChatGPT: native `response_format` API field (`json_object` / `json_schema`)
  - Gemini: native `response_format` (Interactions API)
  - Ollama: native `format` field; `supportsStructuredOutput(model)` capability check
  - Claude: native `output_config.format`; system-message injection on pre-4.6 models
  - llama.cpp: system message injection
- **llm_vllm** — retries are on by default (a vLLM server answers `503` while loading weights), `TimeoutConfig.totalTimeout` is enforced on streams, `batchEmbed` splits large inputs, and `VLLMRepository.resolveCapabilities()` probes what a deployment actually offers rather than what the backend implements.
- **llm_vllm** — layered request-parameter handling for vLLM's 64-parameter surface: portable settings on `LLMChatOptions`, typed helpers (`VLLMSamplingOptions`, `VLLMStructuredOutputs`) for the vLLM-only knobs, and a validated `backendOptions` map for the long tail. Unknown keys throw with a suggested correction rather than being silently dropped by the server; server configuration can be probed via `VLLMRepository.supportsToolCalling` / `supportsReasoningParser` / `fetchSupportedParams`.
- **llm_vllm** — New vLLM OpenAI-compatible backend package: streaming chat, optional API key auth, embeddings, model listing, OpenAI-compatible `response_format` plus vLLM-native `structured_outputs` guided decoding, reasoning via `chat_template_kwargs.enable_thinking`, and multi-instance pooling.

### Changed
- All packages bumped to `0.2.0`; `llm_core` dependency updated to `^0.2.0` across all backend packages

### Fixed
- **llm_vllm** — `RetryConfig.retryableStatusCodes` never applied to streaming requests: a non-2xx is *returned* rather than thrown and the status check ran after the retry wrapper, so retries only fired on transport errors. `think` was mapped to `include_reasoning`, which defaults to `true` and controls only whether reasoning is *surfaced*, not whether the model thinks; `think: false` was therefore silently ignored. Thinking is now gated through `chat_template_kwargs.enable_thinking`. A base URL ending in `/v1` produced `/v1/v1/...` and a 404; `reasoningBudget` caused a hard 400; and the documented `extra_body` guided-decoding pattern was a no-op. Removed `guided_*` names now raise `ArgumentError` rather than silently yielding unconstrained output.
- **llm_claude** — `think: true` failed on every current model (`budget_tokens` returns a 400 on Opus 4.7+), sampling parameters were sent to models that reject them, thinking text was always empty (`display` defaults to `omitted`), and mid-stream SSE `error` events ended the stream as a success with truncated output.
- **llm_core** — `LLMFinishReason.fromProvider` recognized only 8 provider spellings; `stop_sequence`, `refusal`, `model_context_window_exceeded` and Gemini's safety reasons all collapsed to `unknown`.
- Example programs logged through `DefaultLLMLogger`, which emits nothing without a `logging` subscription — every status banner was invisible. Examples now write to stdout.

### CI
- `coverage.yml`, `docs.yml` and `scripts/generate-docs.sh` covered only `llm_core`, `llm_ollama` and `llm_chatgpt`; `llm_vllm`, `llm_claude` and `llm_gemini` are now included.
- `provider-live.yml` did not pass the `VLLM_ENABLE_*` flags, so the vLLM live job silently skipped its tool, reasoning and embedding suites.

## [0.1.8] - 2026-02-26

### Tool Calling Stream Visibility (OpenAI-compliant)

- **llm_core:** Tool result chunks (`role: tool`) emitted to stream; assistant message with `tool_calls` added before tool results; content accumulation; unified `toolCallId` format (removed `toolName`)
- **llm_ollama:** `tool_name` derived from `toolCallId` in Ollama layer; `messagesToOllamaJson()` for list-aware conversion; fallback for empty/missing tool_calls
- **llm_chatgpt, llm_llamacpp:** Version bump for llm_core dependency; no API changes

## [0.1.7] - 2026-02-10

### Added
- **batchEmbed()** on `LLMChatRepository` (llm_core) and implementations in llm_ollama, llm_chatgpt, and llm_llamacpp. Explicit API for embedding multiple texts in one call; same signature as `embed()`, with provider-specific documentation.

## [0.1.5] - 2026-01-26

**First Production Release** - This is the first release suitable for production use. All packages are now published and available on [pub.dev](https://pub.dev/publishers/brynjen/packages).

### 🎉 Major Features

#### Core Infrastructure (`llm_core`)
- **StreamChatOptions**: New class to encapsulate all streaming chat options, reducing parameter proliferation and improving API ergonomics
- **RetryConfig & RetryUtil**: Configurable retry logic with exponential backoff for handling transient failures
- **TimeoutConfig**: Flexible timeout configuration supporting connection, read, total, and large payload timeouts
- **LLMMetrics**: Optional metrics collection interface with `DefaultLLMMetrics` implementation for monitoring LLM operations
- **chatResponse()**: New convenience method on `LLMChatRepository` for non-streaming complete responses that handles tool execution loops internally
- **Input Validation**: Comprehensive validation utilities (`Validation` class) for model names and messages
- **Builder Pattern Support**: `ChatRepositoryBuilderBase` abstract class for implementing builder patterns in repository implementations
- **StreamChatOptionsMerger**: Utility for merging options from multiple sources
- **HTTP Client Utilities**: `HttpClientHelper` for consistent request handling across backends
- **Error Handling**: Standardized error processing with `ErrorHandlers` and `BackendErrorHandler` utilities
- **Tool Execution**: `ToolExecutor` utility for managing tool calling workflows

#### Ollama Backend (`llm_ollama`)
- **Builder Pattern**: `OllamaChatRepositoryBuilder` for complex configurations
- **Advanced Configuration**: Full support for `RetryConfig` and `TimeoutConfig`
- **Input Validation**: Model name and message validation
- **StreamChatOptions Support**: Integration with new options system

#### ChatGPT/OpenAI Backend (`llm_chatgpt`)
- **Builder Pattern**: `ChatGPTChatRepositoryBuilder` for complex configurations
- **Advanced Configuration**: Full support for `RetryConfig` and `TimeoutConfig`
- **Input Validation**: Model name and message validation
- **Improved Stream Parsing**: Enhanced `GptStreamConverter` for better reliability
- **StreamChatOptions Support**: Integration with new options system

#### llama.cpp Backend (`llm_llamacpp`)
- **StreamChatOptions Support**: Integration with new options system
- **Input Validation**: Model name and message validation
- **Improved Isolate Handling**: Enhanced isolate-based inference handling for better performance

### 📦 Package Availability

All packages are now published and available on pub.dev:
- **[llm_core](https://pub.dev/packages/llm_core)** - Core abstractions and interfaces
- **[llm_ollama](https://pub.dev/packages/llm_ollama)** - Ollama backend implementation
- **[llm_chatgpt](https://pub.dev/packages/llm_chatgpt)** - OpenAI/ChatGPT backend implementation
- **[llm_llamacpp](https://pub.dev/packages/llm_llamacpp)** - Local inference via llama.cpp

### 🔄 API Changes

- **Backward Compatible**: All changes are additive and backward compatible
- `streamChat()` now accepts optional `StreamChatOptions` parameter (existing parameter-based API still works)
- Improved error handling and retry logic across all backends
- Enhanced documentation across all packages

### 📚 Documentation & Examples

- Comprehensive Flutter example app (`packages/llm_llamacpp/example_app/`) demonstrating real-world usage
- Enhanced API documentation with detailed examples
- Improved README files for all packages

### 🛠️ Developer Experience

- **Builder Pattern**: Simplified configuration for complex repository setups
- **Better Error Messages**: More actionable error messages with context
- **Validation**: Early validation catches errors before API calls
- **Metrics**: Optional metrics collection for monitoring and debugging

### 🔒 Reliability

- **Retry Logic**: Automatic retry with exponential backoff for transient failures
- **Timeout Configuration**: Flexible timeout handling for different scenarios
- **Error Handling**: Standardized error processing across all backends
- **Input Validation**: Comprehensive validation prevents common errors

## [0.1.0] - 2026-01-19

### Added
- Initial release of llm_ollama package
- Support for Ollama chat streaming with `OllamaChatRepository`
- Support for ChatGPT chat streaming with `ChatGPTChatRepository`
- Tool/function calling support for both backends
- Image support in chat messages
- Thinking support for Ollama
- Basic repository functionality with `OllamaRepository` for model management
- Comprehensive test coverage
- Example implementation
