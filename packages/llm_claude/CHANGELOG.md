# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
