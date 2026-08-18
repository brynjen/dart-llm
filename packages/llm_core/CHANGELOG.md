# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Streaming requests are no longer built with `StreamedRequest`. Every caller passes a fully-materialised body, so `sendStreamingRequest` now uses `http.Request` + `bodyBytes`: `package:http` reports the content length and `dart:io` writes the body as part of `send()`, instead of negotiating chunked encoding and then retracting it via a hand-set `content-length` header.
- `RetryUtil.executeWithRetry` warns on every retry (via `RetryUtil.logger`) and accepts an `onRetry` callback. A request that wedged for a full timeout and then succeeded on retry previously surfaced as latency and nothing else.

### Added
- `createLLMHttpClient()` — the default HTTP client for all backends. Applies `TimeoutConfig.connectionTimeout` (previously never used anywhere), bounds the pool per host (default 64, configurable via `maxConnectionsPerHost`), and drops the idle timeout to 3s so the client, not the server, retires idle connections. Falls back to a plain `http.Client` on web.
- `WriteGatedHttpClient` and `createLLMHttpClient(maxConcurrentWrites: ...)` — a counting semaphore bounds how many requests may be in their connect+request-write phase at once (default 4 on macOS/iOS only; excess requests queue, slots release the moment the body reaches the kernel, streaming responses are never limited, no timers involved). Works around a Dart VM defect in the macOS kqueue event handler: sockets opened and written in the same instant can lose their writable event, so the request bytes never leave the process — no error, connection ESTABLISHED on both ends. Root-caused with kernel counters on both ends and a raw-`Socket` repro; Linux is unaffected. Bounded admission matches httpx/aiohttp/LiteLLM practice; a per-request write watchdog additionally aborts any residual stall as a retryable `TimeoutException`. Requires `http >= 1.5.0` (abort support). See `llm_vllm`'s `BUG-concurrent-send-stall.md`.

### Changed
- Dependency floors raised: Dart SDK `^3.12.0` (was `^3.8.0`), `http ^1.6.0`; dev deps refreshed (`lints ^6.1.0`, `test ^1.31.0`) and new lint findings fixed (null-aware elements, private named initializing formals).
- **Behaviour change:** `HttpClientHelper.sendStreamingRequest`'s `applyTimeoutToSend` now defaults to `true`. It previously defaulted to `false`, which returned an entirely untimed `send()` — a request that wedged before response headers arrived never recovered.


## [0.3.0] - 2026-08-17

### Added
- `ReasoningEffort` enum (`none`…`max`) and `LLMChatOptions.reasoningEffort` —
  a portable reasoning-depth knob alongside `reasoningBudget`.
- `reasoningEffortForBudget()` for backends without a native token budget.
- `LLMUsage.reasoningTokens` for providers that report reasoning-token usage.

## [0.2.0] - 2026-08-12

### Fixed
- `LLMFinishReason.fromProvider` now recognizes `stop_sequence`, `model_context_window_exceeded`, `refusal`, and Gemini's `RECITATION` / `PROHIBITED_CONTENT` / `BLOCKLIST` / `SPII` / `IMAGE_SAFETY`, which previously all collapsed to `unknown`.

### Added
- `LLMFinishReason.refusal` for provider safety declines, which arrive as successful responses with empty or partial content.
- Typed message content parts, typed tool calls, provider capabilities, response usage, finish reasons, thinking output, and provider metadata.
- `LLMChatOptions` for generation, reasoning, tool behavior, structured output, timeout, retry, cache, metrics, and backend-specific options.
- Shared repository feature helpers for cache and metrics handling.
- `LLMResponseFormat` sealed class hierarchy for structured output:
  - `JsonFormat` — simple JSON mode; instructs the model to produce valid JSON without schema enforcement
  - `JsonSchemaFormat({required name, required schema, strict = true})` — full JSON Schema mode; schema is forwarded to the backend verbatim
  - Both are `const`-constructible and work with exhaustive `switch` pattern matching
- `responseFormat` field on `StreamChatOptions` (nullable, defaults to `null`; fully backward compatible)
- `StreamChatOptionsMerger` and `MergedOptions` now carry and propagate `responseFormat`

### Changed
- **Breaking:** Core chat APIs now accept `LLMChatOptions?`; `StreamChatOptions` remains as a compatibility alias.
- Cache keys now use stable JSON-shaped request data instead of object stringification.

## [0.1.9] - 2026-02-28

### Changed
- **Breaking:** Removed `requireFinalAssistantResponse` option from `StreamChatOptions`, `StreamChatOptionsMerger`, and `StreamToolExecutor`. Tool loops now always require a final assistant response — there is no reason to allow tool loops to end without the assistant reporting back.
- `maxToolAttempts` default increased from 25 to 90 across all repositories and builders.
- `chatResponse()` tool loop detection refined: only actual tool result chunks (`LLMRole.tool`) trigger the incomplete-loop check, not tool calls appearing alongside content.

## [0.1.8] - 2026-02-26

### Added
- Tool result chunks emitted to stream: `StreamToolExecutor` now yields `LLMChunk` with `role: LLMRole.tool` after each tool execution, so chat consumers can display "Tool X returned: Y" per OpenAI function calling specs
- `LLMToolCall.toApiFormat()` helper for converting to OpenAI/Ollama API format
- Assistant message with `tool_calls` added to message history before tool results (API-compliant sequence)
- Content accumulation from stream chunks for assistant messages that include both text and tool calls

### Changed
- **Breaking:** Removed `toolName` from `LLMMessage` and `LLMChunkMessage`; use `toolCallId` only (OpenAI canonical format)
- **Breaking:** Tool message validation now requires `toolCallId` (removed `toolName` option)
- `StreamToolExecutor` accumulates content and thinking from chunks for the assistant message

## [0.1.7] - 2026-02-10

### Added
- `batchEmbed()` on `LLMChatRepository`: explicit API for embedding multiple texts in one call. Same signature as `embed()`; default implementation delegates to `embed()`. Documented for Ollama, OpenAI, and llama.cpp backends.

## [0.1.6] - 2026-02-10

### Fixed
- Hardened `StreamToolExecutor` to always synthesize a non-empty `toolCallId` for `LLMRole.tool` messages when a backend-provided `LLMToolCall.id` is missing or empty, preventing `Tool message must have toolCallId` validation errors.
- Improved tool execution error handling so that thrown tool exceptions are surfaced as tool messages rather than crashing the stream.

## [0.1.5] - 2026-01-26

### Added
- `StreamChatOptions` class to encapsulate all streaming chat options and reduce parameter proliferation
- `RetryConfig` and `RetryUtil` for configurable retry logic with exponential backoff
- `TimeoutConfig` for flexible timeout configuration (connection, read, total, large payloads)
- `LLMMetrics` interface and `DefaultLLMMetrics` implementation for optional metrics collection
- `chatResponse()` method on `LLMChatRepository` for non-streaming complete responses
- Input validation utilities in `Validation` class
- `ChatRepositoryBuilderBase` for implementing builder patterns in repository implementations
- `StreamChatOptionsMerger` for merging options from multiple sources
- HTTP client utilities (`HttpClientHelper`) for consistent request handling
- Error handling utilities (`ErrorHandlers`, `BackendErrorHandler`) for standardized error processing
- Tool execution utilities (`ToolExecutor`) for managing tool calling workflows

### Changed
- `streamChat()` now accepts optional `StreamChatOptions` parameter
- Improved error handling and retry logic across all backends
- Enhanced documentation

## [0.1.0] - 2026-01-19

### Added
- Initial release
- Core abstractions for LLM interactions:
  - `LLMChatRepository` - Abstract interface for chat completions
  - `LLMMessage` - Message representation with roles and content
  - `LLMResponse` - Response wrapper with metadata
  - `LLMChunk` - Streaming response chunks
  - `LLMEmbedding` - Text embedding representation
- Tool calling support:
  - `LLMTool` - Tool definition with JSON Schema parameters
  - `LLMToolCall` - Tool invocation representation
  - `LLMToolParam` - Parameter definitions
- Exception types for error handling
