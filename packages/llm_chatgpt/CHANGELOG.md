# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-04-09

### Added
- Structured output support via `StreamChatOptions.responseFormat`:
  - `JsonFormat()` → `response_format: {type: "json_object"}` (native OpenAI API)
  - `JsonSchemaFormat(name, schema, strict)` → `response_format: {type: "json_schema", json_schema: {name, strict, schema}}` (native OpenAI API)
  - `responseFormat` is propagated through tool-call loops so format constraints are preserved across all turns
- Bumped `llm_core` dependency to `^0.2.0`

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
