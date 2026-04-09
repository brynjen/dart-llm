# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-04-09

### Added
- Initial release of the Anthropic Claude backend for the dart-llm ecosystem
- Streaming chat responses via the Anthropic Messages API (`/v1/messages`)
- Tool/function calling with automatic tool-loop execution (`autoExecuteTools: true`)
- Thinking mode support (`think: true`) with configurable token budget via `backendOptions['thinking_budget']`
- Structured output via `StreamChatOptions.responseFormat`:
  - `JsonFormat()` — injects a "respond with valid JSON only" instruction into the system field
  - `JsonSchemaFormat(name, schema)` — injects the JSON Schema into the system field; appended after any user-defined system content
  - `responseFormat` is propagated through tool-call loops so format constraints are preserved across all turns
- `ClaudeChatRepository.builder()` for fluent configuration
- `RetryConfig` and `TimeoutConfig` support for resilient production deployments
- Full compatibility with `LLMChatRepository` interface from `llm_core`
