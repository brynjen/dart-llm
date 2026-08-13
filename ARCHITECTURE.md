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
│   ├── llm_vllm/          # vLLM OpenAI-compatible backend (depends on llm_core)
│   ├── llm_chatgpt/       # OpenAI/ChatGPT backend (depends on llm_core)
│   ├── llm_llamacpp/      # llama.cpp local inference (depends on llm_core)
│   ├── llm_claude/        # Anthropic Claude backend (depends on llm_core)
│   └── llm_gemini/        # Google Gemini backend (depends on llm_core)
```

### Dependency Graph

```
llm_core (base)
    ↑
    ├── llm_ollama
    ├── llm_vllm
    ├── llm_chatgpt
    ├── llm_llamacpp
    ├── llm_claude
    └── llm_gemini
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

### Structured Output Architecture

Structured output forces the model to produce valid JSON, optionally conforming to a user-supplied schema. The core type is a sealed class hierarchy:

```dart
sealed class LLMResponseFormat {
  const LLMResponseFormat();
}

/// Simple JSON mode — model produces valid JSON, no schema enforced.
final class JsonFormat extends LLMResponseFormat {
  const JsonFormat();
}

/// Full JSON Schema mode — model output must conform to [schema].
final class JsonSchemaFormat extends LLMResponseFormat {
  const JsonSchemaFormat({
    required this.name,
    required this.schema,
    this.strict = true,
  });
  final String name;
  final Map<String, dynamic> schema;
  final bool strict;
}
```

**Usage**:
```dart
final options = StreamChatOptions(
  responseFormat: JsonSchemaFormat(
    name: 'person',
    schema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'age': {'type': 'integer'},
      },
      'required': ['name', 'age'],
    },
  ),
);
```

**Per-Backend Implementation**:

| Backend | Mechanism | Notes |
|---|---|---|
| `llm_chatgpt` | Native `response_format` field | `json_object` or `json_schema` with `strict` |
| `llm_vllm` | Native OpenAI-compatible `response_format` field | `json_object` or `json_schema` with `strict`; vLLM-native `structured_outputs` (regex / choice / grammar) via `VLLMStructuredOutputs` |
| `llm_gemini` | Native `response_format` (Interactions API) | Chat uses `POST /v1beta/interactions`; the legacy `generateContent` endpoint is deprecated by Google |
| `llm_ollama` | Native `format` field | `"json"` string or schema object; schema requires model support |
| `llm_claude` | Native `output_config.format` | `json_schema` on Opus 4.6+ / Sonnet 5 / Fable 5; system-message injection on older models |
| `llm_llamacpp` | System message injection | Instruction prepended/appended to system message |

**Tool-Loop Propagation**: All backends forward `responseFormat` in the `StreamChatOptions` used for recursive tool-call rounds, ensuring the constraint is preserved across all iterations.

## Package Details

### llm_core

**Purpose**: Foundation layer providing common abstractions.

**Key Components**:

1. **LLMChatRepository**: Abstract interface for chat operations
2. **LLMMessage**: Message representation with roles (user, assistant, system, tool)
3. **LLMChunk**: Streaming response chunks
4. **LLMResponse**: Complete response wrapper
5. **LLMTool**: Tool definition interface
6. **LLMResponseFormat**: Structured output format (sealed class: `JsonFormat`, `JsonSchemaFormat`)
7. **Exceptions**: Common exception types
8. **Validation**: Input validation utilities
9. **RetryConfig**: Retry logic configuration
10. **TimeoutConfig**: Timeout configuration
11. **StreamChatOptions**: Encapsulates all streaming options (including `responseFormat`)

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
- Structured output (JSON mode and JSON Schema)

**Implementation Details**:
- Uses HTTP client for API communication
- Supports Ollama-specific features (thinking tokens)
- Handles SSE (Server-Sent Events) streaming
- Implements retry logic with exponential backoff
- `supportsStructuredOutput(model)` queries `/api/show` capabilities for schema support

### llm_chatgpt

**Purpose**: OpenAI/ChatGPT backend implementation.

**Features**:
- Streaming chat
- Tool/function calling
- Embeddings
- Azure OpenAI compatibility
- Native structured output (`json_object` and `json_schema` modes)

**Implementation Details**:
- Uses HTTP client for API communication
- Supports OpenAI API format
- Handles streaming responses

### llm_vllm

**Purpose**: vLLM OpenAI-compatible backend implementation.

**Features**:
- Streaming chat
- Tool/function calling
- Vision payloads through OpenAI-compatible message content
- Embeddings
- Model listing
- Native structured output (`json_object` and `json_schema` modes)
- Multi-instance pool routing and health checks

**Implementation Details**:
- Uses vLLM's OpenAI-compatible `/v1/chat/completions`, `/v1/embeddings`, and `/v1/models` endpoints
- Supports optional bearer auth for servers started with `--api-key`
- Handles SSE streaming responses and vLLM reasoning deltas
- Implements retry logic with exponential backoff
- Configurable base URL with `/v1` normalization (`normalizeVllmBaseUrl`)
- Validates `backendOptions` against vLLM's parameter schema, with camelCase
  aliases and typo suggestions, because vLLM silently drops unknown fields

### llm_llamacpp

**Purpose**: Local inference via llama.cpp.

**Features**:
- GGUF model support
- Streaming generation
- Multiple prompt templates
- Tool calling via prompt convention
- GPU acceleration support
- Isolate-based inference
- Structured output via system message injection

**Implementation Details**:
- Uses FFI to call native llama.cpp libraries
- Supports multiple platforms (Linux, macOS, Windows, Android, iOS)
- Handles model loading and context management
- Implements prompt templates for different model families
- `injectResponseFormat()` pure function prepends/appends to system message

### llm_claude

**Purpose**: Anthropic Claude backend implementation.

**Features**:
- Streaming chat
- Tool/function calling, including `tool_choice`
- Model-aware thinking: adaptive on current models, token budget on older ones
- Native structured output via `output_config.format`
- Configurable base URL (custom endpoints)

**Implementation Details**:
- Uses HTTP client for Anthropic Messages API
- Handles streaming SSE responses
- Structured output achieved by appending schema instructions to the system prompt
- No native embeddings API (throws `UnsupportedError`)
- Implements retry logic with exponential backoff

### llm_gemini

**Purpose**: Google Gemini backend implementation.

**Features**:
- Streaming chat via the Interactions API (`POST /v1beta/interactions`)
- Tool/function calling
- Thinking, with thought summaries surfaced on `chunk.message.thinking`
- Native structured output (`response_format`)
- Embeddings (`embedContent` / `batchEmbedContents`)

**Implementation Details**:
- Chat targets the Interactions API; Google labels the `generateContent`
  endpoint legacy
- The API key is sent as the `x-goog-api-key` header rather than a `key=`
  query parameter, so it does not leak into logs or proxies
- Streaming is a step machine (`step.start` / `step.delta` / `step.stop`)
  rather than a `candidates[]` array; `arguments_delta` fragments are
  concatenated to form tool-call arguments
- `thought_signature` values are captured and exposed via
  `LLMChunk.providerMetadata`, which multi-turn function calling requires
- Implements retry logic with exponential backoff

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
  responseFormat: JsonSchemaFormat(name: 'result', schema: {...}),
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
// or
LLMChatRepository repo = ClaudeChatRepository(...);
// or
LLMChatRepository repo = GeminiChatRepository(...);
```

## Extension Points

### Adding a New Backend

1. **Create a new package** in `packages/`
2. **Add dependency** on `llm_core` (workspace resolution):
   ```yaml
   dependencies:
     llm_core: ^0.2.0
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
5. **Handle structured output** if the API supports it natively, otherwise inject via system message
6. **Propagate responseFormat** in tool-loop `StreamChatOptions` construction
7. **Handle tool execution** if supported
8. **Export** the repository in `lib/my_backend.dart`

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

1. **Caching Layer**: Response caching for cost reduction
2. **Rate Limiting**: Built-in rate limiting
3. **Observability**: Enhanced metrics and tracing
4. **Batch Processing**: Batch API support
5. **Additional Backends**: Other LLM providers as they mature

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
