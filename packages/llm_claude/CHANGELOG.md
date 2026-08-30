# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-08-30

### Fixed
- A truncated tool call no longer runs with **no arguments**. Accumulated tool input was decoded and re-encoded, and anything unparseable was swallowed into `{}` — so a turn cut short by `max_tokens`, or the fine-grained tool streaming beta (which emits unvalidated partial JSON by design), produced a tool call that executed with empty arguments instead of failing. The wire text is now passed through verbatim, so truncation surfaces as an error at execution. This also makes the completed call byte-identical to its concatenated `toolCallDeltas`, as on every other backend.
- Mid-stream `error` events now carry a `statusCode`. Anthropic reports failures by `type` rather than a numeric code, and retry classification works off the status code, so a mid-stream `overloaded_error` or `rate_limit_error` was never recognized as retryable. Types are mapped to their documented HTTP equivalents (`overloaded_error` → 529).

### Added
- Streaming tool calls surface as they arrive on `LLMChunkMessage.toolCallDeltas`. Claude names the tool in a dedicated `content_block_start` event, so the name is reported before a single argument byte exists.
- `extraHeaders` on `ClaudeChatRepository` and its builder. This makes `anthropic-beta` reachable for the first time — for example `fine-grained-tool-streaming-2025-05-14`, which streams tool parameters without server-side buffering. Protocol headers, `x-api-key` and `anthropic-version` always take precedence.

## [0.3.2] - 2026-08-18

### Changed
- Version bumped to `0.3.2` in lockstep with the other packages, and the `llm_core` constraint raised to `^0.3.2`. No other changes to this package.

## [0.3.1] - 2026-08-18

### Fixed
- `streamChat` applies a timeout to the send operation. It previously opted out, so a request that wedged before response headers arrived never recovered.
- The default HTTP client is now `createLLMHttpClient()`, which applies `TimeoutConfig.connectionTimeout` and bounds the connection pool.

### Changed
- Dependency floors raised: Dart SDK `^3.12.0` (was `^3.8.0`), `http ^1.6.0`, `lints ^6.1.0`, `test ^1.31.0`.

## [0.3.0] - 2026-08-17

### Added
- `reasoningEffort` support: maps to `output_config.effort` on current models
  (wins over a budget-derived level) and converts to `budget_tokens` on
  legacy models via `claudeBudgetForEffort`.

## [0.2.0] - 2026-08-12

Initial release of the Anthropic Claude backend for the dart-llm ecosystem.

### Added

- `ClaudeChatRepository` — streaming chat via the Anthropic Messages API
  (`POST /v1/messages`, `x-api-key`, `anthropic-version: 2023-06-01`).
- Tool/function calling with automatic tool-loop execution
  (`autoExecuteTools: true`), plus `tool_choice` accepting either the Messages
  API object form or OpenAI-style shorthands (`auto`, `required`, `none`, or a
  tool name). Failed tool results are marked `is_error: true`.
- Model-aware thinking. Current models (Opus 4.7+, Sonnet 5, Fable 5,
  Mythos 5) use `thinking: {type: 'adaptive', display: 'summarized'}`; older
  models use `budget_tokens`, clamped below `max_tokens`.
  `LLMChatOptions.reasoningBudget` maps to an `output_config.effort` level on
  models that no longer accept token budgets.
- Structured output via `LLMChatOptions.responseFormat`, using the native
  `output_config.format` field where available and falling back to
  system-prompt injection on older models. Propagated through tool-call loops
  so the constraint holds across every turn.
- Vision support for base64 image content with MIME-type sniffing.
- `ClaudeRequestShape` and the `claudeSupports*` helpers, which resolve the
  request shape a given model id expects. Unrecognized ids are treated as
  current models, so newly released models work without a library update.
- Cache token counts (`cache_creation_input_tokens`, `cache_read_input_tokens`)
  and thinking-block signatures are surfaced through
  `LLMChunk.providerMetadata`.
- `ClaudeChatRepository.builder()` for fluent configuration, with retry,
  timeout, rate limiting, response cache, and metrics support.
- Unit test suites asserting the exact request body per model family, and
  key-gated integration suites.

### Notes on the Messages API

Two request shapes were **removed** rather than deprecated on newer models, so
sending the old form is a hard `400` rather than an ignored field:

| Request shape | Opus 4.7+, Sonnet 5, Fable 5, Mythos 5 | Older models |
|---|---|---|
| `thinking: {type: 'enabled', budget_tokens: N}` | **400** | supported |
| `temperature` / `top_p` / `top_k` | **400** | supported |

`llm_claude` selects the correct shape from the model id, so sampling
parameters are omitted for models that reject them rather than failing the
request. Steer those models through the prompt instead.

`thinking.display` defaults to `omitted` on current models, which returns
thinking blocks with empty text; `llm_claude` requests `summarized` so
`chunk.message.thinking` is populated.

### Verification status

The request shapes above are covered by unit tests asserting the serialized
JSON body. They have **not** been exercised against the live Anthropic API —
the integration suites are key-gated and were not run for this release.
