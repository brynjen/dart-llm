# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **llm_vllm** — correctness sweep (0.3.0): camelCase `toolChoice` and other aliased keys now reliably reach the wire (`backendOptions` is normalized once after validation); caller-supplied `chat_template_kwargs` merge with `enable_thinking` instead of clobbering it, so `think:` is always honored; `tool_choice` without tools is applied (`none`/`auto`) or rejected with a clear error (`required`/named); malformed 200 bodies from `/v1/embeddings` and `/v1/models` raise `LLMApiException` instead of `TypeError`; the stream converter flushes partial `<think>` carries at end of stream and stamps in-stream error codes as `statusCode`; `embed` options are validated like chat options.

### Changed
- **llm_vllm** — `VLLMPool` mixes in `LLMRepositoryFeatures` (pool-level `responseCache`/`metrics`), reports aggregated `capabilitiesForModel`, forwards `toolAttempts` and per-instance `rateLimiter`/`supportedParams`/`capabilities`/`httpClient`, batches `batchEmbed` through the selected instance, and enforces `maxQueueDepth` race-free. Dead non-streaming DTOs (`VLLMResponse`, `VLLMChoice`, `VLLMMessage`) and the unreachable builder extension were removed (breaking; see the package CHANGELOG). Package version bumped to 0.3.0.

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
