# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-04-09

### Added
- Initial release of the Google Gemini backend for the dart-llm ecosystem
- Streaming chat responses via the Gemini API (`streamGenerateContent`)
- Tool/function calling with automatic tool-loop execution (`autoExecuteTools: true`)
- Thinking mode support (`think: true`) with configurable token budget via `backendOptions['thinking_budget']`
- Native embeddings via `embed()` and `batchEmbed()` (single and batch endpoints)
- Structured output via `StreamChatOptions.responseFormat` (native `generationConfig` API):
  - `JsonFormat()` → `responseMimeType: "application/json"`
  - `JsonSchemaFormat(name, schema)` → `responseMimeType: "application/json"` + `responseSchema: {schema}`
  - Note: Gemini `responseSchema` uses UPPERCASE type names (`"STRING"`, `"OBJECT"`, etc.)
  - `responseFormat` is propagated through tool-call loops so format constraints are preserved across all turns
- `generationConfig` options via `backendOptions` (`temperature`, `topP`, `topK`, `maxOutputTokens`, `stopSequences`, `responseMimeType`)
- `GeminiChatRepository.builder()` for fluent configuration
- `RetryConfig` and `TimeoutConfig` support for resilient production deployments
- Full compatibility with `LLMChatRepository` interface from `llm_core`
