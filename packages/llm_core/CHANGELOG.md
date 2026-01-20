# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-19

### Added

- Initial release
- Core abstractions for LLM interactions:
  - `LLMChatRepository` - Abstract interface for chat completions
  - `LLMMessage` - Message representation with roles and content
  - `LLMResponse` - Response wrapper with metadata
  - `LLMChunk` - Streaming response chunks
  - `LLMEmbedding` - Text embedding representation
- Tool calling support:
  - `LLMTool` - Tool definition with JSON Schema parameters
  - `LLMToolCall` - Tool invocation representation
  - `LLMToolParam` - Parameter definitions
- Exception types for error handling
