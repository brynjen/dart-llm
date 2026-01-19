# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-19

### Added

- Initial release
- Core abstractions for LLM interactions:
  - `LlmChatRepository` - Abstract interface for chat completions
  - `LlmMessage` - Message representation with roles and content
  - `LlmResponse` - Response wrapper with metadata
  - `LlmChunk` - Streaming response chunks
  - `LlmEmbedding` - Text embedding representation
- Tool calling support:
  - `LlmTool` - Tool definition with JSON Schema parameters
  - `LlmToolCall` - Tool invocation representation
  - `LlmToolParam` - Parameter definitions
- Exception types for error handling
