# llm_ollama

Ollama backend implementation for LLM interactions in Dart.

## Features

- Streaming chat responses
- Tool/function calling
- Vision (image) support
- Embeddings
- Thinking mode support
- Model management (list, pull, show, version)

## Installation

```yaml
dependencies:
  llm_ollama:
    git:
      url: https://github.com/brynjen/dart-llm.git
      path: packages/llm_ollama
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

### Using StreamChatOptions

Encapsulate all options in a single object:

```dart
import 'package:llm_core/llm_core.dart';

final options = StreamChatOptions(
  think: true,
  tools: [MyTool()],
  toolAttempts: 5,
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
);

final stream = repo.streamChat('qwen3:0.6b', messages: messages, options: options);
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

