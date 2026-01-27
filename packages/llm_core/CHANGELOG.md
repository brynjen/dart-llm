# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.5] - 2026-01-26

### Added
- `StreamChatOptions` class to encapsulate all streaming chat options and reduce parameter proliferation
- `RetryConfig` and `RetryUtil` for configurable retry logic with exponential backoff
- `TimeoutConfig` for flexible timeout configuration (connection, read, total, large payloads)
- `LLMMetrics` interface and `DefaultLLMMetrics` implementation for optional metrics collection
- `chatResponse()` method on `LLMChatRepository` for non-streaming complete responses
- Input validation utilities in `Validation` class
- `ChatRepositoryBuilderBase` for implementing builder patterns in repository implementations
- `StreamChatOptionsMerger` for merging options from multiple sources
- HTTP client utilities (`HttpClientHelper`) for consistent request handling
- Error handling utilities (`ErrorHandlers`, `BackendErrorHandler`) for standardized error processing
- Tool execution utilities (`ToolExecutor`) for managing tool calling workflows

### Changed
- `streamChat()` now accepts optional `StreamChatOptions` parameter
- Improved error handling and retry logic across all backends
- Enhanced documentation

## [0.1.0] - 2026-01-19

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
