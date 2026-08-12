# llm_ollama

[![pub.dev](https://img.shields.io/pub/v/llm_ollama)](https://pub.dev/packages/llm_ollama)

Ollama backend implementation for LLM interactions in Dart.

Available on [pub.dev](https://pub.dev/packages/llm_ollama).

## Features

- Streaming chat responses
- Tool/function calling
- Vision (image) support
- Embeddings
- Thinking mode support
- Model management (list, pull, show, version)

## Streaming Reliability Guarantees

- NDJSON chunk-boundary-safe parsing: stream frames are buffered across transport chunks and parsed only when newline-terminated
- Bounded malformed-line retries: parser tolerates up to 3 consecutive malformed non-empty lines
- Explicit failure on persistent corruption: parser throws `LLMApiException` after retry budget exhaustion (no silent infinite dropping)

## Installation

```yaml
dependencies:
  llm_ollama: ^0.2.0
```

## Prerequisites

You need Ollama running locally or on a server. Install from [ollama.com](https://ollama.com/).

```bash
# Pull a model
ollama pull qwen3:0.6b
```

## Usage

### Basic Chat

```dart
import 'package:llm_ollama/llm_ollama.dart';

final repo = OllamaChatRepository(baseUrl: 'http://localhost:11434');

final stream = repo.streamChat('qwen3:0.6b', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  print(chunk.message?.content ?? '');
}
```

### With Thinking Mode

```dart
final stream = repo.streamChat('qwen3:0.6b',
  messages: messages,
  think: true, // Enable thinking mode
);

await for (final chunk in stream) {
  if (chunk.message?.thinking != null) {
    print('Thinking: ${chunk.message!.thinking}');
  }
  print(chunk.message?.content ?? '');
}
```

### Tool Calling

```dart
final stream = repo.streamChat('qwen3:0.6b',
  messages: messages,
  tools: [MyTool()],
);
```

### Vision

```dart
import 'dart:convert';
import 'dart:io';

final imageBytes = await File('image.png').readAsBytes();
final base64Image = base64Encode(imageBytes);

final stream = repo.streamChat('llama3.2-vision:11b', messages: [
  LLMMessage(
    role: LLMRole.user,
    content: 'What is in this image?',
    images: [base64Image],
  ),
]);
```

### Structured Output

Use `LLMChatOptions.responseFormat` to request structured JSON output:

```dart
import 'package:llm_core/llm_core.dart';

// Simple JSON mode — works on all models
final stream = repo.streamChat(
  'qwen3:0.6b',
  messages: [LLMMessage(role: LLMRole.user, content: 'List three fruits as JSON.')],
  options: const LLMChatOptions(responseFormat: JsonFormat()),
);

// JSON Schema mode — requires a model with structured_outputs capability
// Check support first:
final repo_mgmt = OllamaRepository();
final supportsSchema = await repo_mgmt.supportsStructuredOutput('llama3.2');

const schema = {
  'type': 'object',
  'properties': {
    'name': {'type': 'string'},
    'age': {'type': 'integer'},
  },
  'required': ['name', 'age'],
};

final stream = repo.streamChat(
  'llama3.2',
  messages: [LLMMessage(role: LLMRole.user, content: 'Return a person object.')],
  options: const LLMChatOptions(
    responseFormat: JsonSchemaFormat(name: 'Person', schema: schema),
  ),
);
```

### Embeddings

```dart
final embeddings = await repo.embed(
  model: 'nomic-embed-text',
  messages: ['Hello world', 'Goodbye world'],
);
```

### Non-Streaming Response

Get a complete response without streaming:

```dart
final response = await repo.chatResponse('qwen3:0.6b', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

print(response.content);
print('Tokens: ${response.evalCount}');
```

### Using LLMChatOptions

Encapsulate all options in a single object:

```dart
import 'package:llm_core/llm_core.dart';

final options = LLMChatOptions(
  think: true,
  tools: [MyTool()],
  toolAttempts: 5,
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
);

final stream = repo.streamChat('qwen3:0.6b', messages: messages, options: options);
```

### Python-Style Parity Options

`llm_ollama` defaults to automatic tool execution for backward compatibility.
If you want `ollama-python` style manual tool loops, disable auto-execution and
consume `toolCalls` directly from streamed chunks.

```dart
final stream = repo.streamChat(
  'qwen3:0.6b',
  messages: messages,
  tools: [MyTool()],
  options: const LLMChatOptions(
    autoExecuteTools: false, // Manual tool loop
  ),
);

await for (final chunk in stream) {
  final toolCalls = chunk.message?.toolCalls ?? const [];
  if (toolCalls.isNotEmpty) {
    // Execute tools yourself, append tool messages, then call streamChat again.
  }
}
```

You can also pass Ollama chat fields supported by `ollama-python`:

```dart
final stream = repo.streamChat(
  'qwen3:0.6b',
  messages: messages,
  options: const LLMChatOptions(
    backendOptions: {
      'format': 'json',
      'options': {'temperature': 0},
      'keep_alive': '5m', // or keepAlive
    },
  ),
);
```

### Model Management

```dart
final ollamaRepo = OllamaRepository(baseUrl: 'http://localhost:11434');

// List models
final models = await ollamaRepo.models();

// Show model info
final info = await ollamaRepo.showModel('qwen3:0.6b');

// Pull a model
await for (final progress in ollamaRepo.pullModel('qwen3:0.6b')) {
  print('${progress.status}: ${progress.progress * 100}%');
}

// Get version
final version = await ollamaRepo.version();
```

## Advanced Configuration

### Builder Pattern

Use the builder for complex configurations:

```dart
import 'package:llm_core/llm_core.dart';

final repo = OllamaChatRepository.builder()
  .baseUrl('http://localhost:11434')
  .maxToolAttempts(10)
  .retryConfig(RetryConfig(
    maxAttempts: 5,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
  ))
  .timeoutConfig(TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 3),
    totalTimeout: Duration(minutes: 10),
  ))
  .build();
```

### Retry Configuration

Configure automatic retries for failed requests:

```dart
import 'package:llm_core/llm_core.dart';

final repo = OllamaChatRepository(
  baseUrl: 'http://localhost:11434',
  retryConfig: RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    retryableStatusCodes: [429, 500, 502, 503, 504],
  ),
);
```

### Timeout Configuration

Configure timeouts for different scenarios:

```dart
import 'package:llm_core/llm_core.dart';

final repo = OllamaChatRepository(
  baseUrl: 'http://localhost:11434',
  timeoutConfig: TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 2),
    totalTimeout: Duration(minutes: 10),
    readTimeoutForLargePayloads: Duration(minutes: 5), // For large images
  ),
);
```
