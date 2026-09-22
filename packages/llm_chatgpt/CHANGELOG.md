# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] - 2026-09-22

### Added
- `LLMUsage.cachedTokens` from `prompt_tokens_details.cached_tokens`, which was parsed and then dropped.

### Fixed
- `RetryConfig.retryableStatusCodes` never applied to streaming requests. A non-2xx arrives as a *returned* response rather than a thrown error, so the retry around the send never saw it and a 429 or 503 from OpenAI failed on the first attempt.
- A failure reported in-band — `200`, then an `error` event on the stream — was not retried either, because it arrives after the send has returned. Both are now re-issued while nothing has reached the caller.
- Parsing `prompt_tokens_details` threw when OpenAI sent the object without `cached_tokens`.
- Cancelling a `streamChat` subscription aborts the request.

### Changed
- `LLMChatOptions.usagePerChunk` is ignored: `continuous_usage_stats` is a vLLM extension and OpenAI's `stream_options` has no equivalent.
- All packages bumped to `0.7.0`; `llm_core` constraint updated to `^0.7.0`.

## [0.6.0] - 2026-09-17

### Changed
- Tool calls are no longer dropped on `length` or at an abrupt end of stream. Calls whose arguments don't decode are returned in `invalidToolCalls`.

## [0.5.0] - 2026-09-11

### Fixed
- Embedding an empty string failed with a 400. OpenAI embeds a bare `""` but rejects an array containing one ("Invalid 'input[0]': input cannot be an empty string"), and `embed` always sent an array. A single input is now sent as a bare string — the shape OpenAI's own examples use, and the only one that can represent an empty input.
- A complete tool call was dropped whenever the turn ended with `finish_reason: "stop"`, which OpenAI reports intermittently and OpenAI-compatible servers report deterministically for a named `tool_choice`.
- A `finish_reason: "tool_calls"` frame with no calls accumulated emitted no terminal chunk at all, so the stream ended with nothing marked `done`: `chatResponse` reported no usage and a fabricated `stop`, and the tool loop raised `ToolLoopIncompleteException`. Every terminal frame now yields exactly one terminal chunk.
- A complete tool call was dropped when the stream ended without a terminal frame — a proxy cutoff or a server hiccup.

### Changed
- A turn that ends while carrying complete tool calls now reports `LLMFinishReason.toolCalls`, whatever the provider spelled. The OpenAI specification defines `finish_reason` as `tool_calls` "if the model called a tool", and providers violate it routinely. Code branching on `LLMFinishReason.stop` for a tool-calling turn must move to `toolCalls`. `length`, `contentFilter` and `refusal` are never reclassified: a truncated call is not executable, and a declined turn must stay visibly declined.

## [0.4.0] - 2026-08-30

### Added
- Streaming tool calls surface as they arrive on `LLMChunkMessage.toolCallDeltas`, instead of being withheld until the call finishes.
- `extraHeaders` on `ChatGPTChatRepository` and its builder — arbitrary headers on every request, including embeddings. Protocol headers and `authorization` always take precedence.

### Fixed
- Mid-stream `error` events are raised instead of ignored. Parsed as an ordinary frame such an event has no choices and no usage, so it was skipped and the stream ended as a *success* carrying a truncated answer. The error's code is surfaced as `statusCode` so a mid-stream 429 or 503 is classified as retryable.
- Streamed tool call fragments are correlated by `index` rather than by `id`. Continuation fragments carry no `id` by design, and the previous fallback attributed them to the most recently seen call.
- Parallel tool calls stay separate when a server or proxy emits all of them with `index: 0`. A fragment whose `id` differs from the call open at that index now starts a new call instead of being merged into it.
- Non-streaming responses kept only the **first** tool call and silently discarded the rest, so a model that asked for parallel calls had all but one dropped — the caller ran one tool and answered as though that were the whole request. The same truncation applied when converting an assistant message back for replay, which rewrote history and taught the model its other calls never happened.
- `GPTToolCall.fromJson` tolerates a missing `index` instead of throwing into the converter's catch-all, where the whole event was silently dropped.

### Changed
- The empty priming delta is no longer yielded.

## [0.3.2] - 2026-08-18

### Changed
- Version bumped to `0.3.2` in lockstep with the other packages, and the `llm_core` constraint raised to `^0.3.2`. No other changes to this package.

## [0.3.1] - 2026-08-18

### Fixed
- The default HTTP client is now `createLLMHttpClient()`, which applies `TimeoutConfig.connectionTimeout` and bounds the connection pool.
- Documentation no longer claims Azure OpenAI compatibility. Azure needs a different URL layout and an `api-key` header; this package always sends `$baseUrl/v1/chat/completions` with a bearer token. Vision and reasoning-model support, both real, are now documented.

### Changed
- Dependency floors raised: Dart SDK `^3.12.0` (was `^3.8.0`), `http ^1.6.0`, `lints ^6.1.0`, `test ^1.31.0`.

## [0.3.0] - 2026-08-17

### Added
- Reasoning-model support: per-model detection (`gptIsReasoningModel`),
  `reasoningEffort`/`reasoningBudget` mapped to a clamped `reasoning_effort`,
  and sampling params dropped where the API rejects them.
- Streaming usage via `stream_options.include_usage`, including
  `LLMUsage.reasoningTokens`.
- Reasoning deltas from OpenAI-compatible servers surface as
  `chunk.message.thinking`.

### Fixed
- `reasoningBudget` no longer hardcodes `reasoning_effort: 'low'`.
- Streamed deltas without a `role` (everything after the first delta) were
  dropped when folding responses and broke tool loops; they now default to
  the assistant role.

## [0.2.0] - 2026-08-12

### Added
- Provider-local functional integration coverage for manual tool calls, automatic tool execution, structured output, and low-cost live-test model defaults.
- Builder support for metrics, response cache, and rate limiting.
- Structured output support via `StreamChatOptions.responseFormat`:
  - `JsonFormat()` → `response_format: {type: "json_object"}` (native OpenAI API)
  - `JsonSchemaFormat(name, schema, strict)` → `response_format: {type: "json_schema", json_schema: {name, strict, schema}}` (native OpenAI API)
  - `responseFormat` is propagated through tool-call loops so format constraints are preserved across all turns
- Bumped `llm_core` dependency to `^0.2.0`

### Changed
- Requests now honor per-call timeout, retry, generation, cache, and metrics options.
- OpenAI live tests default to `gpt-5.4-nano` for chat and `text-embedding-3-small` for embeddings.

### Fixed
- `autoExecuteTools: false` now exposes tool calls without executing them.
- HTTP client ownership and disposal are deterministic.

## [0.1.9] - 2026-02-28

### Changed
- `maxToolAttempts` default increased from 25 to 90
- Bumped `llm_core` dependency to ^0.1.9

## [0.1.8] - 2026-02-26

### Changed
- Bumped `llm_core` dependency to ^0.1.8 for tool calling stream visibility

## [0.1.7] - 2026-02-10

### Added
- `batchEmbed()` implementation: delegates to existing batch-capable `embed()` (OpenAI embeddings API accepts array of strings).

## [0.1.6] - 2026-02-10

### Fixed
- Ensured conversion from ChatGPT `tool_calls` to `LLMToolCall` always yields non-null, non-empty `id` values, synthesizing IDs should the OpenAI response omits them.
- Improved interoperability with `llm_core`'s strict `toolCallId` validation for tool messages in tool-calling workflows.

## [0.1.5] - 2026-01-26

### Added
- Builder pattern for `ChatGPTChatRepository` via `ChatGPTChatRepositoryBuilder` for complex configurations
- Support for `StreamChatOptions` in `streamChat()` method
- Support for `chatResponse()` method for non-streaming complete responses
- Support for `RetryConfig` and `TimeoutConfig` for advanced request configuration
- Input validation for model names and messages
- Improved stream parsing with `GptStreamConverter`

### Changed
- `streamChat()` now accepts optional `StreamChatOptions` parameter
- Improved error handling and retry logic
- Enhanced documentation

## [0.1.0] - 2026-01-19

### Added
- Initial release
- OpenAI/ChatGPT backend implementation for LLM interactions:
  - Streaming chat responses
  - Tool/function calling support
  - Embeddings
  - Compatible with Azure OpenAI
- Full compatibility with OpenAI API
