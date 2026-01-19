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
      url: https://github.com/brynjen/dart-ollama.git
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

