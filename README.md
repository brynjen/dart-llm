[![CI](https://github.com/brynjen/dart-ollama/actions/workflows/ci.yaml/badge.svg)](https://github.com/brynjen/dart-ollama/actions/workflows/ci.yaml)

# Dart LLM

A Dart monorepo for interacting with Large Language Models (LLMs). Supports multiple backends including Ollama, ChatGPT/OpenAI, and local inference via llama.cpp.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [llm_core](packages/llm_core/) | Core abstractions and interfaces | - |
| [llm_ollama](packages/llm_ollama/) | Ollama backend | - |
| [llm_chatgpt](packages/llm_chatgpt/) | OpenAI/ChatGPT backend | - |
| [llm_llamacpp](packages/llm_llamacpp/) | Local inference via llama.cpp | - |

## Features

* 🚀 **Streaming chat responses** - Real-time streaming of chat responses
* 🔧 **Tool/function calling** - Support for function calling and tool use
* 🖼️ **Image support** - Send images in chat messages (vision models)
* 🤖 **Multiple backends** - Ollama, ChatGPT, and local llama.cpp
* 💭 **Thinking support** - Support for Ollama's thinking feature
* 📦 **Easy to use** - Simple and intuitive API
* 📱 **Cross-platform** - Works on mobile (Android/iOS) and desktop

## Quick Start

### Using Ollama

```dart
import 'package:llm_ollama/llm_ollama.dart';

Future<void> main() async {
  final repo = OllamaChatRepository(baseUrl: 'http://localhost:11434');
  
  final stream = repo.streamChat('qwen3:0.6b', messages: [
    LLMMessage(role: LLMRole.system, content: 'Answer short and concise'),
    LLMMessage(role: LLMRole.user, content: 'Why is the sky blue?'),
  ], think: true);
  
  await for (final chunk in stream) {
    print(chunk.message?.content ?? '');
  }
}
```

### Using ChatGPT/OpenAI

```dart
import 'package:llm_chatgpt/llm_chatgpt.dart';

Future<void> main() async {
  final repo = ChatGPTChatRepository(apiKey: 'your-api-key');
  
  final stream = repo.streamChat('gpt-4o', messages: [
    LLMMessage(role: LLMRole.user, content: 'Hello, ChatGPT!'),
  ]);
  
  await for (final chunk in stream) {
    print(chunk.message?.content ?? '');
  }
}
```

### Using llama.cpp (Local Inference)

```dart
import 'package:llm_llamacpp/llm_llamacpp.dart';

Future<void> main() async {
  final repo = LlamaCppChatRepository(
    contextSize: 2048,
    nGpuLayers: 0, // Set > 0 for GPU acceleration
  );
  
  try {
    await repo.loadModel('/path/to/model.gguf');
    
    final stream = repo.streamChat('model', messages: [
      LLMMessage(role: LLMRole.user, content: 'Hello!'),
    ]);
    
    await for (final chunk in stream) {
      print(chunk.message?.content ?? '');
    }
  } finally {
    repo.dispose();
  }
}
```

## Installation

Add the package(s) you need to your `pubspec.yaml`:

```yaml
dependencies:
  # For Ollama backend
  llm_ollama:
    git:
      url: https://github.com/brynjen/dart-ollama.git
      path: packages/llm_ollama

  # For ChatGPT/OpenAI backend
  llm_chatgpt:
    git:
      url: https://github.com/brynjen/dart-ollama.git
      path: packages/llm_chatgpt

  # For local llama.cpp inference
  llm_llamacpp:
    git:
      url: https://github.com/brynjen/dart-ollama.git
      path: packages/llm_llamacpp
```

## Package Details

### llm_core

Core abstractions shared by all backends:

- `LLMChatRepository` - Interface for chat repositories
- `LLMMessage`, `LLMRole` - Message and role types
- `LLMChunk`, `LLMChunkMessage` - Streaming chunk types
- `LLMTool`, `LLMToolParam`, `LLMToolCall` - Tool/function calling types
- `LLMEmbedding` - Embedding types
- Exceptions: `ThinkingNotSupportedException`, `ToolsNotSupportedException`, `VisionNotSupportedException`, `LLMApiException`

### llm_ollama

Ollama backend features:

- Streaming chat with thinking support
- Tool/function calling
- Vision (image) support
- Embeddings
- Model management (list, pull, show, version)

### llm_chatgpt

OpenAI/ChatGPT backend features:

- Streaming chat
- Tool/function calling
- Embeddings
- Compatible with Azure OpenAI (configure `baseUrl`)

### llm_llamacpp

Local llama.cpp inference:

- GGUF model support
- Streaming generation
- Multiple prompt templates (ChatML, Llama2, Llama3, Alpaca, Vicuna, Phi-3)
- Tool calling via prompt convention
- GPU acceleration support
- Isolate-based inference (non-blocking)

Supported platforms:
- Linux (x86_64)
- macOS (arm64, x86_64)
- Windows (x86_64)
- Android (arm64-v8a, x86_64)
- iOS (arm64)

## Tool/Function Calling

All backends support tool calling:

```dart
class CalculatorTool extends LLMTool {
  @override
  String get name => 'calculator';

  @override
  String get description => 'Performs arithmetic calculations';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'expression',
      type: 'string',
      description: 'The math expression to evaluate',
      isRequired: true,
    ),
  ];

  @override
  Future<String> execute(Map<String, dynamic> args, {dynamic extra}) async {
    final expr = args['expression'] as String;
    // ... evaluate expression ...
    return result.toString();
  }
}

// Use with any backend
final stream = repo.streamChat('model',
  messages: messages,
  tools: [CalculatorTool()],
);
```

## Development

This is a Dart monorepo using path dependencies for local development.

```bash
# Get dependencies for all packages
cd packages/llm_core && dart pub get
cd ../llm_ollama && dart pub get
cd ../llm_chatgpt && dart pub get
cd ../llm_llamacpp && dart pub get

# Run tests
cd packages/llm_ollama && dart test
cd ../llm_chatgpt && dart test

# Build llama.cpp native libraries
# See .github/workflows/build-llamacpp.yaml
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
