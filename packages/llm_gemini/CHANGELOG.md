# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `streamChat` now applies a timeout to the send operation. `sendStreamingRequest` previously defaulted to no send timeout, so a request that wedged before response headers arrived never recovered.
- The default HTTP client is now `createLLMHttpClient()`, which applies `TimeoutConfig.connectionTimeout` and bounds the connection pool.

### Changed
- Dependency floors raised: Dart SDK `^3.12.0` (was `^3.8.0`), `http ^1.6.0`; dev deps refreshed (`lints ^6.1.0`, `test ^1.31.0`) and new lint findings fixed (null-aware elements, private named initializing formals).


## [0.3.0] - 2026-08-17

### Added
- `reasoningEffort` maps to `thinking_level` (wins over the budget mapping).
- Thought-token usage surfaced as `LLMUsage.reasoningTokens`.

### Fixed
- Migrated to the Interactions API's steps-based input format (`user_input`/
  `model_output`/`function_call` steps) — the old turn-based format is now
  rejected by the live API.
- Tool loops echo the model's thought signature (required by the API), carried
  through the tool-call id.
- Structured output sends the JSON schema inline; the `json_schema` wrapper
  type is rejected by the live API.
- `think: false` sent `thinking_summaries: 'off'`, which the live API rejects
  with a 400; it now sends `'none'`.
- Empty user messages sent an empty text block (a 400); now a single-space
  block, the only shape the API accepts for a degenerate empty message.

## [0.2.0] - 2026-08-12

Initial release of the Google Gemini backend for the dart-llm ecosystem.

### Added

- `GeminiChatRepository` — streaming chat via the **Interactions API**
  (`POST /v1beta/interactions`). Google labels the older `generateContent`
  endpoint legacy, so this package targets Interactions from the outset.
  Requests carry `model`, `input`, `stream`, `store`, `tools`,
  `response_format`, and `generation_config`; responses are parsed from
  `interaction.created`, `step.start`, `step.delta`, `step.stop`, and
  `interaction.completed` events.
- The API key is sent in the `x-goog-api-key` **header**, for chat and
  embeddings alike — never appended to the URL as `key=…`, where it would leak
  into logs, proxies, and crash reports.
- Stateless by default: requests send `store: false` and serialize the whole
  conversation into `input` as role-tagged turns, matching
  `LLMChatRepository`'s stateless contract. Server-side continuation is opt-in
  via `backendOptions['previous_interaction_id']`.
- Tool/function calling with automatic tool-loop execution
  (`autoExecuteTools: true`). Declarations are sent as a flat `tools` array of
  `{"type": "function", "name", "description", "parameters"}` entries. Tool
  calls carry the server-provided call id, and argument JSON is assembled by
  concatenating `arguments_delta` fragments.
- Thinking, with `thought_summary` deltas populating
  `LLMChunkMessage.thinking` and `text` deltas populating
  `LLMChunkMessage.content` — the two are kept separate rather than reasoning
  being emitted as ordinary assistant output.
  `LLMChatOptions.reasoningBudget` maps onto the discrete
  `generation_config.thinking_level` (`minimal`/`low`/`medium`/`high`); the
  Interactions API has no raw token budget. Override with
  `backendOptions['thinking_level']`.
- `thought_signature` values are accumulated per step index and surfaced via
  `LLMChunk.providerMetadata['thought_signatures']`.
- Structured output via `LLMChatOptions.responseFormat`, mapped onto the
  `response_format` array. Standard lowercase JSON Schema is forwarded
  unchanged. Propagated through tool-call loops so the constraint holds across
  every turn.
- Embeddings via `embed()` and `batchEmbed()` (`embedContent` /
  `batchEmbedContents`).
- Usage mapping for the Interactions field names (`total_tokens`,
  `total_input_tokens`, `total_output_tokens`, `total_cached_tokens`,
  `total_thought_tokens`, `total_tool_use_tokens`); thought, cached and total
  counts are surfaced through `LLMChunk.providerMetadata` alongside
  `interaction_id`.
- `GeminiChatRepository.builder()` for fluent configuration, with retry,
  timeout, rate limiting, response cache, and metrics support.

### Notes

- `topP`, `topK` and `stopSequences` are not sent: the Interactions
  `generation_config` documents no equivalent. Pass them through
  `backendOptions['generation_config']` if your account supports them.
- Defaults and docs use `gemini-3.5-flash-lite`. The `gemini-3.1-flash-lite`
  id referenced during development does not appear in Google's published model
  list.

### Verification status

This package has **not** been exercised against the live Gemini API — there was
no API key available. Coverage is unit tests asserting the serialized request
body and parsed stream events; the integration suites are key-gated and unrun.

Two shapes are **inferred from prose rather than read from a specification**
and are the first things to check if requests fail with HTTP 400:

- The role-tagged `input` turn envelope
  (`{"role": "user"|"model", "content": [ … ]}`), together with the `text`,
  `function_call` and `image` input blocks and the placement of
  `function_result` blocks on a `user` turn. All of this is confined to
  `GeminiMessageConverter.buildStatelessInput`, which documents each
  assumption individually.
- The `response_format` element shape
  (`[{"type": "json_object"}]` / `[{"type": "json_schema", "name", "schema"}]`);
  only the fact that it is an array is documented.

Known limitation: `thought_signature` values are surfaced on the response, but
Google documents no input block for echoing them back, so multi-turn function
calling may still hit "Function call is missing a thought_signature".
