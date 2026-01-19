# Architecture

This document describes the architecture, design decisions, and extension points of the Dart LLM project.

## Overview

Dart LLM is a monorepo providing a unified interface for interacting with Large Language Models (LLMs) across multiple backends. The architecture is designed around a core abstraction layer (`llm_core`) that defines common interfaces, with backend-specific implementations.

## Package Structure

```
dart-llm/
├── packages/
│   ├── llm_core/          # Core abstractions (no dependencies on other packages)
│   ├── llm_ollama/        # Ollama backend (depends on llm_core)
│   ├── llm_chatgpt/       # OpenAI/ChatGPT backend (depends on llm_core)
│   └── llm_llamacpp/      # llama.cpp local inference (depends on llm_core)
```

### Dependency Graph

```
llm_core (base)
    ↑
    ├── llm_ollama
    ├── llm_chatgpt
    └── llm_llamacpp
```

**Key Principle**: `llm_core` has no dependencies on backend packages, ensuring clean separation and allowing backends to be used independently.

## Core Architecture

### Repository Pattern

The project uses the Repository pattern to abstract LLM interactions:

```dart
abstract class LLMChatRepository {
  Stream<LLMChunk> streamChat(...);
  Future<LLMResponse> chatResponse(...);
  Future<List<LLMEmbedding>> embed(...);
}
```

**Benefits**:
- **Unified Interface**: All backends implement the same interface
- **Easy Swapping**: Switch between backends without changing application code
- **Testability**: Mock repositories for testing
- **Extensibility**: Add new backends by implementing the interface

### Streaming-First Design

The architecture is designed around streaming responses:

1. **Primary Method**: `streamChat()` returns a `Stream<LLMChunk>`
2. **Convenience Method**: `chatResponse()` collects chunks internally
3. **Real-time Updates**: Applications can display tokens as they're generated

**Rationale**:
- Better user experience (progressive rendering)
- Lower memory usage (no need to buffer full response)
- Supports long-running conversations

### Tool Calling Architecture

Tool calling is integrated into the core interface:

```dart
abstract class LLMTool {
  String get name;
  String get description;
  List<LLMToolParam> get parameters;
  Future<String> execute(Map<String, dynamic> args, {dynamic extra});
}
```

**Flow**:
1. User provides tools to `streamChat()`
2. Model requests tool execution via tool calls
3. Repository automatically executes tools
4. Tool results are added to conversation
5. Process repeats until final response

**Design Decisions**:
- **Automatic Execution**: Tools are executed automatically (no manual intervention)
- **Loop Handling**: Repository handles the tool execution loop internally
- **Extra Context**: `extra` parameter allows passing user context to tools
- **Backend Agnostic**: Tool interface works across all backends

## Package Details

### llm_core

**Purpose**: Foundation layer providing common abstractions.

**Key Components**:

1. **LLMChatRepository**: Abstract interface for chat operations
2. **LLMMessage**: Message representation with roles (user, assistant, system, tool)
3. **LLMChunk**: Streaming response chunks
4. **LLMResponse**: Complete response wrapper
5. **LLMTool**: Tool definition interface
6. **Exceptions**: Common exception types
7. **Validation**: Input validation utilities
8. **RetryConfig**: Retry logic configuration
9. **TimeoutConfig**: Timeout configuration
10. **StreamChatOptions**: Encapsulates all streaming options

**Design Principles**:
- **No Backend Dependencies**: Core doesn't know about specific backends
- **Validation**: Input validation at the interface level
- **Flexibility**: Options classes for complex configurations
- **Extensibility**: Easy to add new features without breaking changes

### llm_ollama

**Purpose**: Ollama backend implementation.

**Features**:
- Streaming chat with thinking support
- Tool/function calling
- Vision (image) support
- Embeddings
- Model management

**Implementation Details**:
- Uses HTTP client for API communication
- Supports Ollama-specific features (thinking tokens)
- Handles SSE (Server-Sent Events) streaming
- Implements retry logic with exponential backoff

### llm_chatgpt

**Purpose**: OpenAI/ChatGPT backend implementation.

**Features**:
- Streaming chat
- Tool/function calling
- Embeddings
- Azure OpenAI compatibility

**Implementation Details**:
- Uses HTTP client for API communication
- Supports OpenAI API format
- Handles streaming responses
- Configurable base URL for Azure compatibility

### llm_llamacpp

**Purpose**: Local inference via llama.cpp.

**Features**:
- GGUF model support
- Streaming generation
- Multiple prompt templates
- Tool calling via prompt convention
- GPU acceleration support
- Isolate-based inference

**Implementation Details**:
- Uses FFI to call native llama.cpp libraries
- Supports multiple platforms (Linux, macOS, Windows, Android, iOS)
- Handles model loading and context management
- Implements prompt templates for different model families

## Design Patterns

### Builder Pattern

Complex configurations use builders:

```dart
final repo = OllamaChatRepository.builder()
  .baseUrl('http://localhost:11434')
  .retryConfig(RetryConfig(maxAttempts: 3))
  .timeoutConfig(TimeoutConfig(readTimeout: Duration(minutes: 5)))
  .build();
```

**Benefits**:
- Reduces parameter proliferation
- Provides sensible defaults
- Makes configuration explicit

### Options Pattern

Options classes encapsulate related parameters:

```dart
final options = StreamChatOptions(
  think: true,
  tools: [CalculatorTool()],
  toolAttempts: 5,
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
);
```

**Benefits**:
- Groups related options
- Reduces method signature complexity
- Allows passing options between methods

### Strategy Pattern

Different backends implement the same interface:

```dart
// Can swap backends without changing application code
LLMChatRepository repo = OllamaChatRepository(...);
// or
LLMChatRepository repo = ChatGPTChatRepository(...);
// or
LLMChatRepository repo = LlamaCppChatRepository(...);
```

## Extension Points

### Adding a New Backend

1. **Create a new package** in `packages/`
2. **Add dependency** on `llm_core`:
   ```yaml
   dependencies:
     llm_core:
       path: ../llm_core
   ```
3. **Implement LLMChatRepository**:
   ```dart
   class MyBackendChatRepository implements LLMChatRepository {
     @override
     Stream<LLMChunk> streamChat(...) {
       // Implementation
     }
     
     @override
     Future<LLMResponse> chatResponse(...) {
       // Can use default implementation or override
     }
     
     @override
     Future<List<LLMEmbedding>> embed(...) {
       // Implementation
     }
   }
   ```
4. **Add validation** at the start of methods:
   ```dart
   Validation.validateModelName(model);
   Validation.validateMessages(messages);
   ```
5. **Handle tool execution** if supported
6. **Export** the repository in `lib/my_backend.dart`

### Adding New Features to Core

When adding features to `llm_core`:

1. **Maintain Backward Compatibility**: Use optional parameters or new methods
2. **Update Interface**: Add to `LLMChatRepository` if needed
3. **Provide Default Implementation**: If possible, provide a default that works for all backends
4. **Update All Backends**: Ensure all backends support the new feature (or throw appropriate exceptions)
5. **Document**: Add comprehensive documentation and examples

### Custom Tools

Creating custom tools:

```dart
class MyCustomTool extends LLMTool {
  @override
  String get name => 'my_tool';
  
  @override
  String get description => 'Does something useful';
  
  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'input',
      type: 'string',
      description: 'The input to process',
      isRequired: true,
    ),
  ];
  
  @override
  Future<String> execute(Map<String, dynamic> args, {dynamic extra}) async {
    // Implementation
    return 'Result';
  }
}
```

## Error Handling

### Exception Hierarchy

```
Exception
  ├── LLMApiException (base for API errors)
  │   ├── ThinkingNotSupportedException
  │   ├── ToolsNotSupportedException
  │   └── VisionNotSupportedException
  └── (Backend-specific exceptions)
```

**Design**:
- **Specific Exceptions**: Each error type has its own exception
- **Context**: Exceptions include relevant context (model, message, etc.)
- **Recovery**: Exceptions provide enough information for recovery

### Retry Logic

Retry logic is configurable via `RetryConfig`:

```dart
final retryConfig = RetryConfig(
  maxAttempts: 3,
  initialDelay: Duration(seconds: 1),
  maxDelay: Duration(seconds: 30),
  backoffMultiplier: 2.0,
  retryableStatusCodes: [429, 500, 502, 503, 504],
);
```

**Features**:
- Exponential backoff
- Configurable retryable status codes
- Maximum delay limits

## Testing Strategy

### Unit Tests

- Test individual components in isolation
- Mock dependencies (HTTP clients, repositories)
- Test error conditions

### Integration Tests

- Test full workflows (streaming, tool execution)
- Use real backends when possible (with test models)
- Test error recovery

### Test Utilities

- `MockLLMChatRepository`: Mock implementation for testing
- Test fixtures for common scenarios
- Helper functions for assertions

## Performance Considerations

### Streaming

- **Memory Efficiency**: Stream chunks instead of buffering
- **User Experience**: Progressive rendering
- **Cancellation**: Support stream cancellation

### Connection Pooling

- HTTP clients can be shared across repository instances
- Reduces connection overhead
- Configurable via builder pattern

### Native Libraries (llm_llamacpp)

- Uses isolates for non-blocking inference
- GPU acceleration support
- Memory mapping for large models

## Security Considerations

### API Keys

- Never commit API keys
- Use environment variables
- Support credential injection via builders

### Input Validation

- Validate all inputs at interface level
- Sanitize user-provided content
- Protect against prompt injection

### Network Security

- Always use HTTPS
- Validate SSL certificates
- Support custom certificate validation

## Future Considerations

### Potential Extensions

1. **Additional Backends**: Anthropic, Google, etc.
2. **Caching Layer**: Response caching for cost reduction
3. **Rate Limiting**: Built-in rate limiting
4. **Observability**: Enhanced metrics and tracing
5. **Batch Processing**: Batch API support

### Breaking Changes

When making breaking changes:

1. **Deprecation Period**: Mark old APIs as deprecated
2. **Migration Guides**: Provide clear migration paths
3. **Version Bumping**: Follow semantic versioning
4. **Documentation**: Update all documentation

## Conclusion

The Dart LLM architecture is designed for:
- **Flexibility**: Easy to add new backends
- **Consistency**: Unified interface across backends
- **Extensibility**: Clear extension points
- **Maintainability**: Clean separation of concerns
- **Testability**: Easy to test and mock

This architecture allows the project to grow while maintaining a clean, consistent API for users.
