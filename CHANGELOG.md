# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.5] - 2026-01-26

**First Production Release** - This is the first release suitable for production use. All packages are now published and available on [pub.dev](https://pub.dev/publishers/brynjen/packages).

### 🎉 Major Features

#### Core Infrastructure (`llm_core`)
- **StreamChatOptions**: New class to encapsulate all streaming chat options, reducing parameter proliferation and improving API ergonomics
- **RetryConfig & RetryUtil**: Configurable retry logic with exponential backoff for handling transient failures
- **TimeoutConfig**: Flexible timeout configuration supporting connection, read, total, and large payload timeouts
- **LLMMetrics**: Optional metrics collection interface with `DefaultLLMMetrics` implementation for monitoring LLM operations
- **chatResponse()**: New convenience method on `LLMChatRepository` for non-streaming complete responses that handles tool execution loops internally
- **Input Validation**: Comprehensive validation utilities (`Validation` class) for model names and messages
- **Builder Pattern Support**: `ChatRepositoryBuilderBase` abstract class for implementing builder patterns in repository implementations
- **StreamChatOptionsMerger**: Utility for merging options from multiple sources
- **HTTP Client Utilities**: `HttpClientHelper` for consistent request handling across backends
- **Error Handling**: Standardized error processing with `ErrorHandlers` and `BackendErrorHandler` utilities
- **Tool Execution**: `ToolExecutor` utility for managing tool calling workflows

#### Ollama Backend (`llm_ollama`)
- **Builder Pattern**: `OllamaChatRepositoryBuilder` for complex configurations
- **Advanced Configuration**: Full support for `RetryConfig` and `TimeoutConfig`
- **Input Validation**: Model name and message validation
- **StreamChatOptions Support**: Integration with new options system

#### ChatGPT/OpenAI Backend (`llm_chatgpt`)
- **Builder Pattern**: `ChatGPTChatRepositoryBuilder` for complex configurations
- **Advanced Configuration**: Full support for `RetryConfig` and `TimeoutConfig`
- **Input Validation**: Model name and message validation
- **Improved Stream Parsing**: Enhanced `GptStreamConverter` for better reliability
- **StreamChatOptions Support**: Integration with new options system

#### llama.cpp Backend (`llm_llamacpp`)
- **StreamChatOptions Support**: Integration with new options system
- **Input Validation**: Model name and message validation
- **Improved Isolate Handling**: Enhanced isolate-based inference handling for better performance

### 📦 Package Availability

All packages are now published and available on pub.dev:
- **[llm_core](https://pub.dev/packages/llm_core)** - Core abstractions and interfaces
- **[llm_ollama](https://pub.dev/packages/llm_ollama)** - Ollama backend implementation
- **[llm_chatgpt](https://pub.dev/packages/llm_chatgpt)** - OpenAI/ChatGPT backend implementation
- **[llm_llamacpp](https://pub.dev/packages/llm_llamacpp)** - Local inference via llama.cpp

### 🔄 API Changes

- **Backward Compatible**: All changes are additive and backward compatible
- `streamChat()` now accepts optional `StreamChatOptions` parameter (existing parameter-based API still works)
- Improved error handling and retry logic across all backends
- Enhanced documentation across all packages

### 📚 Documentation & Examples

- Comprehensive Flutter example app (`packages/llm_llamacpp/example_app/`) demonstrating real-world usage
- Enhanced API documentation with detailed examples
- Improved README files for all packages

### 🛠️ Developer Experience

- **Builder Pattern**: Simplified configuration for complex repository setups
- **Better Error Messages**: More actionable error messages with context
- **Validation**: Early validation catches errors before API calls
- **Metrics**: Optional metrics collection for monitoring and debugging

### 🔒 Reliability

- **Retry Logic**: Automatic retry with exponential backoff for transient failures
- **Timeout Configuration**: Flexible timeout handling for different scenarios
- **Error Handling**: Standardized error processing across all backends
- **Input Validation**: Comprehensive validation prevents common errors

## [0.1.0] - 2026-01-19

### Added
- Initial release of llm_ollama package
- Support for Ollama chat streaming with `OllamaChatRepository`
- Support for ChatGPT chat streaming with `ChatGPTChatRepository`
- Tool/function calling support for both backends
- Image support in chat messages
- Thinking support for Ollama
- Basic repository functionality with `OllamaRepository` for model management
- Comprehensive test coverage
- Example implementation
