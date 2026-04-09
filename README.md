[![CI](https://github.com/brynjen/dart-llm/actions/workflows/ci.yaml/badge.svg)](https://github.com/brynjen/dart-llm/actions/workflows/ci.yaml)

# Dart LLM

A Dart monorepo for interacting with Large Language Models (LLMs). Supports multiple backends including Ollama, ChatGPT/OpenAI, Anthropic Claude, Google Gemini, and local inference via llama.cpp.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [llm_core](packages/llm_core/) | Core abstractions and interfaces | [![pub.dev](https://img.shields.io/pub/v/llm_core)](https://pub.dev/packages/llm_core) |
| [llm_ollama](packages/llm_ollama/) | Ollama backend | [![pub.dev](https://img.shields.io/pub/v/llm_ollama)](https://pub.dev/packages/llm_ollama) |
| [llm_chatgpt](packages/llm_chatgpt/) | OpenAI/ChatGPT backend | [![pub.dev](https://img.shields.io/pub/v/llm_chatgpt)](https://pub.dev/packages/llm_chatgpt) |
| [llm_llamacpp](packages/llm_llamacpp/) | Local inference via llama.cpp | [![pub.dev](https://img.shields.io/pub/v/llm_llamacpp)](https://pub.dev/packages/llm_llamacpp) |
| [llm_claude](packages/llm_claude/) | Anthropic Claude backend | [![pub.dev](https://img.shields.io/pub/v/llm_claude)](https://pub.dev/packages/llm_claude) |
| [llm_gemini](packages/llm_gemini/) | Google Gemini backend | [![pub.dev](https://img.shields.io/pub/v/llm_gemini)](https://pub.dev/packages/llm_gemini) |

## Features

* 🚀 **Streaming chat responses** - Real-time streaming of chat responses
* 🔧 **Tool/function calling** - Support for function calling and tool use
* 🖼️ **Image support** - Send images in chat messages (vision models)
* 🤖 **Multiple backends** - Ollama, ChatGPT, Claude, Gemini, and local llama.cpp
* 💭 **Thinking support** - Support for extended reasoning / thinking tokens
* 📋 **Structured output** - Force JSON responses conforming to a schema
* 📦 **Easy to use** - Simple and intuitive API
* 📱 **Cross-platform** - Works on mobile (Android/iOS) and desktop
* ⚙️ **Advanced configuration** - Retry logic, timeouts, and flexible options
* 📊 **Metrics support** - Optional metrics collection for monitoring

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

### Using Claude (Anthropic)

```dart
import 'package:llm_claude/llm_claude.dart';

Future<void> main() async {
  final repo = ClaudeChatRepository(apiKey: 'your-api-key');
  
  final stream = repo.streamChat('claude-opus-4-5', messages: [
    LLMMessage(role: LLMRole.user, content: 'Hello, Claude!'),
  ]);
  
  await for (final chunk in stream) {
    print(chunk.message?.content ?? '');
  }
}
```

### Using Gemini (Google)

```dart
import 'package:llm_gemini/llm_gemini.dart';

Future<void> main() async {
  final repo = GeminiChatRepository(apiKey: 'your-api-key');
  
  final stream = repo.streamChat('gemini-2.0-flash', messages: [
    LLMMessage(role: LLMRole.user, content: 'Hello, Gemini!'),
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
  llm_ollama: ^0.2.0

  # For ChatGPT/OpenAI backend
  llm_chatgpt: ^0.2.0

  # For Anthropic Claude backend
  llm_claude: ^0.2.0

  # For Google Gemini backend
  llm_gemini: ^0.2.0

  # For local llama.cpp inference
  llm_llamacpp: ^0.2.0
```

## Package Details

### llm_core

Core abstractions shared by all backends:

- `LLMChatRepository` - Interface for chat repositories
- `LLMMessage`, `LLMRole` - Message and role types
- `LLMChunk`, `LLMChunkMessage` - Streaming chunk types
- `LLMTool`, `LLMToolParam`, `LLMToolCall` - Tool/function calling types
- `LLMEmbedding` - Embedding types
- `LLMResponseFormat` - Structured output: `JsonFormat`, `JsonSchemaFormat`
- Exceptions: `ThinkingNotSupportedException`, `ToolsNotSupportedException`, `VisionNotSupportedException`, `LLMApiException`

### llm_ollama

Ollama backend features:

- Streaming chat with thinking support
- Tool/function calling
- Vision (image) support
- Embeddings
- Model management (list, pull, show, version)
- Structured output (JSON mode and JSON Schema via native `format` field)

### llm_chatgpt

OpenAI/ChatGPT backend features:

- Streaming chat
- Tool/function calling
- Embeddings
- Compatible with Azure OpenAI (configure `baseUrl`)
- Native structured output (`json_object` and `json_schema` modes)

### llm_claude

Anthropic Claude backend features:

- Streaming chat
- Tool/function calling
- Thinking (extended reasoning) mode
- Structured output via system message injection
- Configurable base URL (custom endpoints)

### llm_gemini

Google Gemini backend features:

- Streaming chat
- Tool/function calling
- Thinking (extended reasoning) mode
- Native structured output (`responseMimeType` + `responseSchema`)
- Embeddings

### llm_llamacpp

Local llama.cpp inference:

- GGUF model support
- Streaming generation
- Multiple prompt templates (ChatML, Llama2, Llama3, Alpaca, Vicuna, Phi-3)
- Tool calling via prompt convention
- GPU acceleration support
- Isolate-based inference (non-blocking)
- Structured output via system message injection

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

## Structured Output

Force the model to respond with valid JSON, optionally conforming to a schema:

```dart
import 'package:llm_core/llm_core.dart';

// Simple JSON mode
final stream = repo.streamChat('model',
  messages: messages,
  options: StreamChatOptions(
    responseFormat: JsonFormat(),
  ),
);

// JSON Schema mode — enforce a specific structure
final stream = repo.streamChat('model',
  messages: messages,
  options: StreamChatOptions(
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
  ),
);
```

Backends implement this natively where supported, and fall back to system-message injection otherwise. See each package's README for backend-specific notes.

## Advanced Configuration

### Using StreamChatOptions

For complex configurations, use `StreamChatOptions` to encapsulate all options:

```dart
import 'package:llm_core/llm_core.dart';

final options = StreamChatOptions(
  think: true,
  tools: [CalculatorTool()],
  toolAttempts: 5,
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
  responseFormat: JsonSchemaFormat(name: 'result', schema: {...}),
);

final stream = repo.streamChat('model', messages: messages, options: options);
```

### Retry Configuration

Configure automatic retries with exponential backoff:

```dart
import 'package:llm_core/llm_core.dart';

final retryConfig = RetryConfig(
  maxAttempts: 3,
  initialDelay: Duration(seconds: 1),
  maxDelay: Duration(seconds: 30),
  backoffMultiplier: 2.0,
  retryableStatusCodes: [429, 500, 502, 503, 504],
);

// Use with builder pattern
final repo = OllamaChatRepository.builder()
  .baseUrl('http://localhost:11434')
  .retryConfig(retryConfig)
  .build();
```

### Timeout Configuration

Configure connection and read timeouts:

```dart
import 'package:llm_core/llm_core.dart';

final timeoutConfig = TimeoutConfig(
  connectionTimeout: Duration(seconds: 10),
  readTimeout: Duration(minutes: 2),
  totalTimeout: Duration(minutes: 10),
  readTimeoutForLargePayloads: Duration(minutes: 5),
);

final repo = ChatGPTChatRepository.builder()
  .apiKey('your-api-key')
  .timeoutConfig(timeoutConfig)
  .build();
```

### Builder Pattern

Use builders for complex repository configurations:

```dart
// Ollama with full configuration
final ollamaRepo = OllamaChatRepository.builder()
  .baseUrl('http://localhost:11434')
  .maxToolAttempts(10)
  .retryConfig(RetryConfig(maxAttempts: 5))
  .timeoutConfig(TimeoutConfig(readTimeout: Duration(minutes: 3)))
  .build();

// ChatGPT with full configuration
final chatgptRepo = ChatGPTChatRepository.builder()
  .apiKey('your-api-key')
  .baseUrl('https://api.openai.com')
  .maxToolAttempts(10)
  .retryConfig(RetryConfig(maxAttempts: 3))
  .timeoutConfig(TimeoutConfig(readTimeout: Duration(minutes: 5)))
  .build();

// Claude with full configuration
final claudeRepo = ClaudeChatRepository.builder()
  .apiKey('your-api-key')
  .maxToolAttempts(10)
  .retryConfig(RetryConfig(maxAttempts: 3))
  .build();

// Gemini with full configuration
final geminiRepo = GeminiChatRepository.builder()
  .apiKey('your-api-key')
  .maxToolAttempts(10)
  .retryConfig(RetryConfig(maxAttempts: 3))
  .build();
```

### Non-Streaming Responses

For use cases where you need the complete response before proceeding:

```dart
// Get complete response (handles tool execution loop internally)
final response = await repo.chatResponse('model', messages: [
  LLMMessage(role: LLMRole.user, content: 'What is 2+2?')
], tools: [CalculatorTool()]);

print(response.content); // Complete response after all tool calls
print('Tokens: ${response.evalCount}');
```

### Metrics Collection

Optional metrics collection for monitoring:

```dart
import 'package:llm_core/llm_core.dart';

final metrics = DefaultLLMMetrics();

// Metrics are automatically recorded by repositories that support them
// Access metrics:
final stats = metrics.getMetrics();
print('Total requests: ${stats['model.total_requests']}');
print('Avg latency: ${stats['model.avg_latency_ms']}ms');
```

## API Documentation

API documentation is automatically generated for all packages. You can:

- **View online**: Check the [pub.dev](https://pub.dev/publishers/brynjen/packages) pages for each package
- **Generate locally**: Run `./scripts/generate-docs.sh` to generate documentation locally
- **CI artifacts**: Documentation is generated in CI and available as artifacts

## Development

This is a Dart monorepo managed with [Melos](https://melos.invertase.dev/).

```bash
# Install Melos
dart pub global activate melos

# Bootstrap all packages
melos bootstrap

# Run all unit tests
melos run test:unit

# Analyze all packages
melos run analyze

# Check formatting
melos run format:check

# Dry-run pub publish for all packages
melos run publish:dry-run
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
