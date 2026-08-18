# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2026-08-18

### Fixed
- A stream read timeout no longer kills the isolate. It is pushed into the sink instead of escaping from `Stream.timeout`'s callback.
- `streamChat` applies a timeout to the send operation. It previously opted out, so a request that wedged before response headers arrived never recovered.
- `pullModel` builds its request with `http.Request` instead of `StreamedRequest` plus a hand-set `content-length`.
- The default HTTP client is now `createLLMHttpClient()`, which applies `TimeoutConfig.connectionTimeout` and bounds the connection pool.

### Changed
- Dependency floors raised: Dart SDK `^3.12.0` (was `^3.8.0`), `http ^1.6.0`, `lints ^6.1.0`, `test ^1.31.0`.

## [0.3.0] - 2026-08-17

### Added
- `think` now supports Ollama's level strings: `reasoningEffort` or
  `reasoningBudget` map to `"low"`/`"medium"`/`"high"`/`"max"`; a bare
  `think: true` stays a bool.

## [0.2.0] - 2026-08-12

### Added
- Builder support for metrics, response cache, and rate limiting.
- Structured output support via `StreamChatOptions.responseFormat`:
  - `JsonFormat()` → `format: "json"` (works on all Ollama models)
  - `JsonSchemaFormat(name, schema)` → `format: {schema}` (schema object passed directly; requires a model with `structured_outputs` capability)
  - `responseFormat` takes precedence over the legacy `backendOptions['format']` key
  - `responseFormat` is propagated through tool-call loops so format constraints are preserved across all turns
- `OllamaRepository.supportsStructuredOutput(String model)` — queries `/api/show` capabilities array for `"structured_outputs"`; mirrors the existing `supportsVision()` pattern
- Bumped `llm_core` dependency to `^0.2.0`

### Changed
- Requests now honor per-call timeout, retry, generation, cache, metrics, and backend-specific options.

### Fixed
- HTTP client ownership and disposal are deterministic.

## [0.1.9] - 2026-02-28

### Added
- Integration regression coverage for stream boundary resilience in tool-call loops (`read_file -> write_file -> final assistant response`)

### Changed
- `OllamaStreamConverter.toLLMStream()` now uses boundary-safe NDJSON line framing across transport chunks
- Stream parsing now uses bounded malformed-line retries (3 consecutive malformed non-empty lines) and throws explicit `LLMApiException` after budget exhaustion instead of silently dropping indefinitely
- `maxToolAttempts` default increased from 25 to 90
- Bumped `llm_core` dependency to ^0.1.9

## [0.1.8] - 2026-02-26

### Added
- `OllamaMessageConverter.messagesToOllamaJson()` for list-aware conversion; derives `tool_name` from `toolCallId` via preceding assistant's `tool_calls` or synthetic ID parsing
- Fallback chain for tool_name: lookup by id, parse synthetic `tool_N_name`, or send `tool_call_id` only (Ollama supports both)
- Thorough tool response integration tests (15 cases) validating stream contract, deterministic results, error handling, tool chains, and Ollama-specific behavior

### Changed
- Tool messages now converted via `messagesToOllamaJson()`; `tool_name` encapsulated in Ollama layer, derived from `toolCallId`
- Replaced per-message `toJson()` with list-aware `messagesToOllamaJson()` for correct tool message conversion

## [0.1.7] - 2026-02-10

### Added
- `batchEmbed()` implementation: delegates to existing batch-capable `embed()` (Ollama `/api/embed` accepts an array of inputs).

## [0.1.6] - 2026-02-10

### Fixed
- Ensured Ollama tool calls always produce `LLMToolCall` instances with non-null, non-empty `id` values, synthesizing IDs when Ollama does not provide them.
- Aligned tool-calling behavior with `llm_core`'s `toolCallId` validation so that tool execution no longer fails with `Tool message must have toolCallId` when used together with `llm_core`.

## [0.1.5] - 2026-01-26

### Added
- Builder pattern for `OllamaChatRepository` via `OllamaChatRepositoryBuilder` for complex configurations
- Support for `StreamChatOptions` in `streamChat()` method
- Support for `chatResponse()` method for non-streaming complete responses
- Support for `RetryConfig` and `TimeoutConfig` for advanced request configuration
- Input validation for model names and messages

### Changed
- `streamChat()` now accepts optional `StreamChatOptions` parameter
- Improved error handling and retry logic
- Enhanced documentation

## [0.1.0] - 2026-01-19

### Added
- Initial release
- Ollama backend implementation for LLM interactions:
  - Streaming chat responses
  - Tool/function calling support
  - Vision (image) support
  - Embeddings
  - Thinking mode support
  - Model management (list, pull, show, version)
- Full compatibility with Ollama API
