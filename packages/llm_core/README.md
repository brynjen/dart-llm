# llm_core

Core abstractions for LLM (Large Language Model) interactions in Dart.

This package provides the foundational interfaces and models used by LLM backend implementations such as `llm_ollama`, `llm_chatgpt`, and `llm_llamacpp`.

## Installation

```yaml
dependencies:
  llm_core:
    git:
      url: https://github.com/brynjen/dart-ollama.git
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

