# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `StreamChatOptions` class to encapsulate all streaming chat options and reduce parameter proliferation
- `RetryConfig` and `RetryUtil` for configurable retry logic with exponential backoff
- `TimeoutConfig` for flexible timeout configuration (connection, read, total, large payloads)
- `LLMMetrics` interface and `DefaultLLMMetrics` implementation for optional metrics collection
- Builder pattern for `OllamaChatRepository` and `ChatGPTChatRepository` for complex configurations
- `chatResponse()` method on `LLMChatRepository` for non-streaming complete responses
- Input validation utilities in `Validation` class
- Comprehensive Flutter example app (`example_app/`) demonstrating real-world usage

### Changed
- `streamChat()` now accepts optional `StreamChatOptions` parameter
- Improved error handling and retry logic across all backends
- Enhanced documentation across all packages

## [0.1.5] - 2025-06-12

### Breaking changes
- Removed tools from repository level, added to message instead for more flexible handling

## [0.1.4] - 2025-06-09

### Added
- Fixing of tests for chatgpt and how it handles tools

## [0.1.3] - 2025-06-09

### Added
- To ensure package works on web, switched out all dart:io with http package
- Made the tests more robust; some tool calls could run a tool multiple times instead of just once as desired
- Added more documentation to satisfy pub dev requirements

## [0.1.2] - 2025-06-09

### Added
- Tool handling of arrays with multiple types were missing

## [0.1.1] - 2025-06-09

### Added
- Missed tool handling for arrays, added it and tool test for arrays


## [0.1.0] - 2024-06-08

### Added
- Initial release of dart_ollama package
- Support for Ollama chat streaming with `OllamaChatRepository`
- Support for ChatGPT chat streaming with `ChatGPTChatRepository`
- Tool/function calling support for both backends
- Image support in chat messages
- Thinking support for Ollama
- Basic repository functionality with `OllamaRepository` for model management
- Comprehensive test coverage
- Example implementation

### Features
- Streaming chat responses
- Tool/function calling
- Image support
- Multiple backend support (Ollama and ChatGPT)
- Thinking support for Ollama
- Model management utilities
