# llm_core

Core abstractions for LLM (Large Language Model) interactions in Dart.

This package provides the foundational interfaces and models used by LLM backend implementations such as `llm_ollama`, `llm_chatgpt`, and `llm_llamacpp`.

## Installation

```yaml
dependencies:
  llm_core:
    git:
      url: https://github.com/brynjen/dart-llm.git
      path: packages/llm_core
```

## Core Types

### Messages

```dart
// Create messages for conversation
final messages = [
  LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
  LLMMessage(role: LLMRole.assistant, content: 'Hi there!'),
];
```

### Repository Interface

```dart
abstract class LLMChatRepository {
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    StreamChatOptions? options, // Optional: encapsulates all options
  });

  Future<LLMResponse> chatResponse(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    StreamChatOptions? options,
  });

  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  });
}
```

### Tools

```dart
class MyTool extends LLMTool {
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
    return 'Result: ${args['input']}';
  }
}
```

### StreamChatOptions

Encapsulates all optional parameters for `streamChat()` to reduce parameter proliferation:

```dart
final options = StreamChatOptions(
  think: true,
  tools: [MyTool()],
  toolAttempts: 5,
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
);

final stream = repo.streamChat('model', messages: messages, options: options);
```

### Retry Configuration

Configure automatic retries with exponential backoff:

```dart
final retryConfig = RetryConfig(
  maxAttempts: 3,                    // Maximum retry attempts
  initialDelay: Duration(seconds: 1), // Initial delay before first retry
  maxDelay: Duration(seconds: 30),    // Maximum delay between retries
  backoffMultiplier: 2.0,            // Exponential backoff multiplier
  retryableStatusCodes: [429, 500, 502, 503, 504], // HTTP codes to retry
);

// Use RetryUtil for custom retry logic
await RetryUtil.executeWithRetry(
  operation: () async => someOperation(),
  config: retryConfig,
  isRetryable: (error) => error is TimeoutException,
);
```

### Timeout Configuration

Configure connection and read timeouts:

```dart
final timeoutConfig = TimeoutConfig(
  connectionTimeout: Duration(seconds: 10),        // Connection timeout
  readTimeout: Duration(minutes: 2),                // Read timeout
  totalTimeout: Duration(minutes: 10),               // Total request timeout
  readTimeoutForLargePayloads: Duration(minutes: 5), // Timeout for large payloads (>1MB)
);

// Get appropriate timeout based on payload size
final timeout = timeoutConfig.getReadTimeoutForPayload(payloadSizeBytes);
```

### Metrics Collection

Optional metrics collection for monitoring LLM operations:

```dart
// Use default implementation
final metrics = DefaultLLMMetrics();

// Metrics are automatically recorded by repositories
// Access collected metrics:
final stats = metrics.getMetrics();
print('Total requests: ${stats['model.total_requests']}');
print('Successful: ${stats['model.successful_requests']}');
print('Failed: ${stats['model.failed_requests']}');
print('Avg latency: ${stats['model.avg_latency_ms']}ms');
print('P95 latency: ${stats['model.p95_latency_ms']}ms');
print('Total tokens: ${stats['model.total_generated_tokens']}');

// Reset metrics
metrics.reset();

// Or implement custom metrics collector
class MyMetrics implements LLMMetrics {
  @override
  void recordRequest({required String model, required bool success}) {
    // Send to your observability stack
  }
  // ... implement other methods
}
```

### Validation

Input validation utilities:

```dart
// Validate model name
Validation.validateModelName('gpt-4o');

// Validate messages
Validation.validateMessages([
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

// Validate tool arguments
Validation.validateToolArguments(
  {'expression': '2+2'},
  'calculator',
);
```

### Exceptions

- `ThinkingNotSupportedException` - Model doesn't support thinking
- `ToolsNotSupportedException` - Model doesn't support tools
- `VisionNotSupportedException` - Model doesn't support vision
- `LLMApiException` - API request failed
- `ModelLoadException` - Model loading failed

## Usage with Backends

This package is typically used indirectly through backend packages:

```dart
import 'package:llm_ollama/llm_ollama.dart'; // Re-exports llm_core

final repo = OllamaChatRepository();
// Use LLMMessage, LLMChunk, etc. from llm_core
```

