# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-08-12

Initial release of the vLLM backend for the dart-llm ecosystem.

### Added

- `VLLMChatRepository` — streaming chat against a vLLM OpenAI-compatible
  server (`/v1/chat/completions`), with tool calling, vision, and automatic
  tool-loop execution.
- Optional API key support for servers started with `--api-key` (sent as
  `Authorization: Bearer`).
- Embeddings via `/v1/embeddings`; model listing via `/v1/models`.
- Structured output through the OpenAI-compatible `response_format` field
  (`json_object` / `json_schema`).
- `VLLMStructuredOutputs` — vLLM-native guided decoding via the top-level
  `structured_outputs` field, with named constructors for `json`, `regex`,
  `choice`, `grammar`, and `structural_tag`.
- `VLLMRepository.resolveCapabilities()` — probes the connected deployment and
  returns an [LLMCapabilities]. `VLLMChatRepository.capabilitiesForModel`
  reports what the *backend* implements (vLLM serves one model per process, so
  tool calling, vision and embeddings vary per deployment); pass the probe
  result as the `capabilities` constructor argument to report what the server
  actually offers. `VLLMRepository.supportsEmbeddings()` added alongside it.
- Retries are on by default (`VLLMChatRepository.defaultRetryConfig`: three
  attempts on `429`/`5xx`). A vLLM server answers `503` while loading weights,
  which was previously a first-attempt failure. Opt out with
  `RetryConfig(maxAttempts: 0)`.
- `TimeoutConfig.totalTimeout` is now applied to streaming responses. It was
  documented as "maximum total time for entire request" but never enforced, so
  a stream that trickled data indefinitely never timed out — `readTimeout`
  only measures the gap *between* chunks.
- `batchEmbed` splits large inputs into batches of
  `defaultEmbeddingBatchSize` (32), preserving order. Override with
  `options['batch_size']`, or pass `0` to send everything in one request.
- `tool_choice` support, accepting `auto` / `none` / `required` or a tool name
  (wrapped in the named-function form). Note both `auto` and `required` require
  the server to run with `--tool-call-parser`.
- `VLLMSamplingOptions` — typed access to the vLLM-only sampling knobs
  (`min_p`, `repetition_penalty`, `min_tokens`, `seed`, `stop_token_ids`,
  `bad_words`, …) plus `vllm_xargs`, vLLM's own escape hatch for
  custom-extension parameters.
- `backendOptions` validation against vLLM's request schema. An unrecognized
  key throws with the closest match (`"repitition_penalty"` → *did you mean
  "repetition_penalty"?*) instead of being silently dropped by the server.
  camelCase spellings are accepted and normalized (`minP` → `min_p`), matching
  `llm_ollama`.
- `VLLMRepository.supportsToolCalling()` and
  `VLLMRepository.supportsReasoningParser()` — server-configuration probes in
  the style of `llm_ollama`'s `supportsStructuredOutput`, returning `false`
  rather than throwing when the server is unreachable.
- `VLLMRepository.fetchSupportedParams()` reads the running server's
  `/openapi.json`, so `backendOptions` can be validated against that server's
  vLLM version rather than the bundled snapshot. Pass it to
  `VLLMChatRepository(supportedParams: ...)`.
- vLLM's terse configuration errors are translated into actionable exceptions:
  a missing `--tool-call-parser` becomes a `ToolsNotSupportedException` naming
  the flag and suggesting a parser for the model family, and a missing
  `--reasoning-parser` becomes a `ThinkingNotSupportedException` explaining
  that thinking still works without it.
- Reasoning control through `chat_template_kwargs.enable_thinking`, sent for
  both `true` and `false` because Qwen3-family models think by default.
  Note this is a different knob from vLLM's `include_reasoning`, which defaults
  to `true` and controls only whether reasoning is *surfaced* — setting it to
  `false` discards the reasoning while the model still spends tokens producing
  it.
  Reasoning text is read from the server's `reasoning` field (aliases
  `reasoning_content`, `thinking`), with a `<think>`-tag splitter as a fallback
  for servers started without `--reasoning-parser`.
- Base URLs are accepted with or without a `/v1` suffix and a trailing slash;
  all spellings resolve to the same endpoint (`normalizeVllmBaseUrl`,
  `vllmEndpoint`).
- `VLLMPool` — multi-instance routing with per-instance and per-model
  concurrency limits, queue limits, health checks, and stats.
- `VLLMChatRepository.builder()` with retry, timeout, rate limiting, response
  cache, and metrics support.
- Unit and integration test suites, including coverage for 16 concurrent
  streams through a single repository.

### Fixed

- **`RetryConfig.retryableStatusCodes` never applied to streaming requests.**
  A non-2xx response is *returned* rather than thrown, and the status check ran
  after the retry wrapper — so retries only ever fired on transport errors, and
  a retryable `429`/`503` failed on the first attempt regardless of
  configuration. Retryable statuses are now raised inside the retried
  operation; non-retryable ones still flow through to the specific exception
  types.
- Embedding errors are routed through `VLLMErrorHandler` and
  `handleHttpError`, so a request against a chat-only model reports the
  server's explanation instead of a generic `'Error generating embedding'`.
  Embeddings also use the same retry policy as chat.

### Notes on vLLM behavior

vLLM **silently ignores unknown request fields** — it returns `200` and drops
them rather than reporting an error, so a misspelled or obsolete parameter is
indistinguishable from a working one. Two guards exist because of this:

- The `guided_*` parameter names removed in vLLM 0.12 raise an `ArgumentError`
  rather than yielding unconstrained output. Use `VLLMStructuredOutputs`.
- `extra_body` is an OpenAI Python SDK wrapper, not a wire field. Its contents
  are flattened onto the request body so they actually reach the server.

`thinking_token_budget` is opt-in via `backendOptions`: vLLM rejects it with a
`400` unless the server was started with `--reasoning-parser` /
`--reasoning-config`.

Tool calling requires the server to run with `--enable-auto-tool-choice` and a
`--tool-call-parser` matching the model's output format.
