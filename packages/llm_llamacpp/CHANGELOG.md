# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-04-09

### Added
- Structured output support via `StreamChatOptions.responseFormat`:
  - `JsonFormat()` — injects a "respond with valid JSON only" instruction into the system message
  - `JsonSchemaFormat(name, schema)` — injects the JSON Schema into the system message
  - If no system message exists, one is prepended; otherwise the instruction is appended to the existing system message
  - `responseFormat` is propagated through tool-call loops so format constraints are preserved across all turns
- `injectResponseFormat(messages, format)` package-private helper function; unit-testable standalone
- Bumped `llm_core` dependency to `^0.2.0`

### Fixed
- Android hosted-package builds now rely on the native-assets hook instead of Gradle invoking repository-local build scripts, and the Android native asset bundle includes the required llama.cpp runtime `.so` dependencies.

## [0.1.9] - 2026-02-28

### Changed
- `maxToolAttempts` default increased from 25 to 90
- Bumped `llm_core` dependency to ^0.1.9

## [0.1.8] - 2026-02-26

### Changed
- Bumped `llm_core` dependency to ^0.1.8 for tool calling stream visibility

## [0.1.7] - 2026-02-10

### Added
- `batchEmbed()` implementation: delegates to existing `embed()` (processes multiple messages in the embedding isolate).

## [0.1.6] - 2026-02-10

### Fixed
- Confirmed that parsed tool calls from llama.cpp outputs always include non-null, non-empty `LLMToolCall.id` values across supported formats (JSON, XML-style, and function-style), maintaining compatibility with `llm_core` tool-calling expectations.
- Added tests for `ToolCallParser` to verify that tool call IDs are populated correctly for downstream `toolCallId` usage.

## [0.1.5] - 2026-01-26

### Added
- Support for `StreamChatOptions` in `streamChat()` method
- Support for `chatResponse()` method for non-streaming complete responses
- Input validation for model names and messages
- Improved isolate-based inference handling

### Changed
- `streamChat()` now accepts optional `StreamChatOptions` parameter
- Improved error handling
- Enhanced documentation

## [0.1.0] - 2026-01-19

### Added
- Initial release
- Local on-device inference with GGUF models via llama.cpp
- Cross-platform support: Android, iOS, macOS, Windows, Linux
- Streaming token generation with isolate-based inference
- Multiple prompt templates: ChatML, Llama2, Llama3, Alpaca, Vicuna, Phi-3
- Tool calling support via prompt convention
- GPU acceleration support (CUDA, Metal, Vulkan)
- Model management features:
  - Model discovery in directories
  - Model loading with pooling (reference counting)
  - GGUF metadata reading without loading
  - HuggingFace model downloading
  - Safetensors to GGUF conversion
- Native Assets build hook for automatic binary management
- Prebuilt binaries available via GitHub Releases
