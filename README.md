[![CI](https://github.com/brynjen/dart-llm/actions/workflows/ci.yaml/badge.svg)](https://github.com/brynjen/dart-llm/actions/workflows/ci.yaml)

# Dart LLM

A Dart monorepo for interacting with Large Language Models (LLMs). Supports multiple backends including Ollama, vLLM, ChatGPT/OpenAI, Anthropic Claude, Google Gemini, and local inference via llama.cpp.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [llm_core](packages/llm_core/) | Core abstractions and interfaces | [![pub.dev](https://img.shields.io/pub/v/llm_core)](https://pub.dev/packages/llm_core) |
| [llm_ollama](packages/llm_ollama/) | Ollama backend | [![pub.dev](https://img.shields.io/pub/v/llm_ollama)](https://pub.dev/packages/llm_ollama) |
| [llm_vllm](packages/llm_vllm/) | vLLM OpenAI-compatible backend | [![pub.dev](https://img.shields.io/pub/v/llm_vllm)](https://pub.dev/packages/llm_vllm) |
| [llm_chatgpt](packages/llm_chatgpt/) | OpenAI/ChatGPT backend | [![pub.dev](https://img.shields.io/pub/v/llm_chatgpt)](https://pub.dev/packages/llm_chatgpt) |
| [llm_claude](packages/llm_claude/) | Anthropic Claude backend | [![pub.dev](https://img.shields.io/pub/v/llm_claude)](https://pub.dev/packages/llm_claude) |
| [llm_gemini](packages/llm_gemini/) | Google Gemini backend | [![pub.dev](https://img.shields.io/pub/v/llm_gemini)](https://pub.dev/packages/llm_gemini) |
| [llm_llamacpp](packages/llm_llamacpp/) | Local inference via llama.cpp | [![pub.dev](https://img.shields.io/pub/v/llm_llamacpp)](https://pub.dev/packages/llm_llamacpp) |

## Features

* 🚀 **Streaming chat responses** - Real-time streaming of chat responses
* 🔧 **Tool/function calling** - Support for function calling and tool use
* 🖼️ **Image support** - Send images in chat messages (vision models)
* 🤖 **Multiple backends** - Ollama, vLLM, ChatGPT, Claude, Gemini, and local llama.cpp
* 💭 **Thinking support** - Support for extended reasoning / thinking tokens
* 📐 **Embeddings** - Single and batched embedding generation
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
  
  final stream = repo.streamChat('gpt-5.4-nano', messages: [
    LLMMessage(role: LLMRole.user, content: 'Hello, ChatGPT!'),
  ]);
  
  await for (final chunk in stream) {
    print(chunk.message?.content ?? '');
  }
}
```

### Using vLLM

```dart
import 'package:llm_vllm/llm_vllm.dart';

Future<void> main() async {
  final repo = VLLMChatRepository(baseUrl: 'http://localhost:8000');
  
  final stream = repo.streamChat('Qwen/Qwen3-0.6B', messages: [
    LLMMessage(role: LLMRole.user, content: 'Hello, vLLM!'),
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
  
  final stream = repo.streamChat('claude-haiku-4-5-20251001', messages: [
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
  
  final stream = repo.streamChat('gemini-3.5-flash-lite', messages: [
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
  // LlamaCppRepository owns model management; LlamaCppChatRepository chats.
  final modelRepo = LlamaCppRepository();
  const modelPath = '/path/to/model.gguf';

  try {
    final model = await modelRepo.loadModel(modelPath);

    final chatRepo = LlamaCppChatRepository.withModel(
      model,
      modelRepo.bindings,
      contextSize: 2048,
      nGpuLayers: 0, // Set > 0 for GPU acceleration
    );

    try {
      final stream = chatRepo.streamChat(modelPath, messages: [
        LLMMessage(role: LLMRole.user, content: 'Hello!'),
      ]);

      await for (final chunk in stream) {
        print(chunk.message?.content ?? '');
      }
    } finally {
      chatRepo.dispose();
    }
  } finally {
    modelRepo.dispose();
  }
}
```

## Installation

Add the package(s) you need to your `pubspec.yaml`:

```yaml
dependencies:
  # For Ollama backend
  llm_ollama: ^0.3.1

  # For vLLM OpenAI-compatible servers
  llm_vllm: ^0.3.1

  # For ChatGPT/OpenAI backend
  llm_chatgpt: ^0.3.1

  # For Anthropic Claude backend
  llm_claude: ^0.3.1

  # For Google Gemini backend
  llm_gemini: ^0.3.1

  # For local llama.cpp inference
  llm_llamacpp: ^0.3.1
```

Each backend depends on `llm_core`, so you only need it directly when writing
your own backend or programming against the abstractions:

```yaml
dependencies:
  llm_core: ^0.3.1
```

## Package Details

### llm_core

Core abstractions shared by all backends:

- `LLMChatRepository` - Interface for chat repositories
- `LLMMessage`, `LLMMessageContent`, `LLMRole` - Typed message content and role types
- `LLMChunk`, `LLMChunkMessage` - Streaming chunk types
- `LLMTool`, `LLMToolParam`, `LLMToolCall` - Tool/function calling types
- `LLMEmbedding` - Embedding types
- `LLMResponse`, `LLMUsage`, `LLMFinishReason` - Response metadata, usage, and finish details
- `LLMResponseFormat` - Structured output: `JsonFormat`, `JsonSchemaFormat`
- `LLMChatOptions` - Per-request generation, reasoning, tool, structured output, timeout, retry, cache, metrics, and provider-specific options
- `LLMCapabilities` + `LLMChatRepository.capabilitiesForModel` - What a model/deployment actually supports
- `createLLMHttpClient()`, `WriteGatedHttpClient` - The shared HTTP client used by every backend
- `RateLimiter`, `ResponseCache`, `LLMMetrics`, `LLMLogger` - Optional cross-cutting concerns
- Exceptions: `ThinkingNotSupportedException`, `ToolsNotSupportedException`, `VisionNotSupportedException`, `ToolLoopIncompleteException`, `ModelLoadException`, `LLMApiException`

### llm_ollama

Ollama backend features:

- Streaming chat with thinking support
- Tool/function calling
- Vision (image) support
- Embeddings
- Model management (list, pull, show, version)
- Structured output (JSON mode and JSON Schema via native `format` field)
- Multi-instance pooling with health checks and per-model routing (`OllamaPool`)

### llm_vllm

vLLM backend features:

- Streaming chat through OpenAI-compatible `/v1/chat/completions`
- Optional bearer auth for servers started with `--api-key`
- Tool/function calling
- Vision payloads through OpenAI-compatible message content
- Embeddings through `/v1/embeddings`
- Model listing through `/v1/models`
- Structured output via OpenAI-compatible `response_format` plus vLLM-native `structured_outputs` guided decoding (regex, choice, grammar)
- Reasoning/thinking through `chat_template_kwargs.enable_thinking`, surfaced separately from content
- Multi-instance pooling with health checks and per-model routing (`VLLMPool`)
- Server-capability probing (`VLLMRepository.resolveCapabilities`, `supportsToolCalling`, `supportsReasoningParser`)

### llm_chatgpt

OpenAI/ChatGPT backend features:

- Streaming chat
- Tool/function calling
- Vision (image) support
- Embeddings
- Reasoning models: per-model detection, `reasoning_effort` mapping, and streaming usage
- Native structured output (`json_object` and `json_schema` modes)
- Configurable base URL for OpenAI-compatible servers

### llm_claude

Anthropic Claude backend features:

- Streaming chat
- Tool/function calling, including `tool_choice`
- Vision (image) support
- Model-aware thinking: adaptive reasoning on current models, token budget on older ones
- Native structured output via `output_config.format` on current models; system-message injection on legacy ones
- Configurable base URL (custom endpoints)
- No embeddings — the Anthropic API offers none, so `embed` throws `UnsupportedError`

### llm_gemini

Google Gemini backend features:

- Streaming chat via the Interactions API (`POST /v1beta/interactions`)
- Tool/function calling
- Thinking with thought summaries surfaced separately from content
- Native structured output (`response_format`)
- Vision input, plus generated images surfaced on `chunk.message.images`
- Embeddings (single and batched)
- API key sent as the `x-goog-api-key` header, never in the URL

### llm_llamacpp

Local llama.cpp inference:

- GGUF model support, with chat templates read from the model file itself
- Streaming generation
- Model-aware tool calling: definitions advertised in the format the loaded model's family expects, calls parsed back out of the raw token stream
- GPU acceleration support
- Isolate-based inference (non-blocking)
- Structured output via system message injection
- Native libraries resolved automatically by the build hook (prebuilt download, source build as fallback)

Supported platforms:
- Linux (x86_64)
- macOS (arm64, x86_64)
- Windows (x86_64)
- Android (arm64-v8a, x86_64)
- iOS (arm64)

## Tool/Function Calling

Every backend can call tools, with two caveats worth knowing before you rely
on it: vLLM needs the server started with `--enable-auto-tool-choice` and a
`--tool-call-parser`, and `llm_llamacpp` parses tool calls out of the raw token
stream rather than from a structured API field, so results depend on the loaded
model's family being recognised.

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
  options: LLMChatOptions(
    responseFormat: JsonFormat(),
  ),
);

// JSON Schema mode — enforce a specific structure
final stream = repo.streamChat('model',
  messages: messages,
  options: LLMChatOptions(
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

### Using LLMChatOptions

For complex configurations, use `LLMChatOptions` to encapsulate all options:

```dart
import 'package:llm_core/llm_core.dart';

final options = LLMChatOptions(
  think: true,
  tools: [CalculatorTool()],
  toolAttempts: 5,
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
  responseFormat: JsonSchemaFormat(
    name: 'result',
    schema: {
      'type': 'object',
      'properties': {'answer': {'type': 'string'}},
      'required': ['answer'],
    },
  ),
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

// vLLM with full configuration
final vllmRepo = VLLMChatRepository.builder()
  .baseUrl('http://localhost:8000')
  .apiKey('optional-api-key')
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
// Keys are prefixed with the model id the request was made against:
print('Total requests: ${stats['qwen3:0.6b.total_requests']}');
print('Avg latency: ${stats['qwen3:0.6b.avg_latency_ms']}ms');
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

## Further reading

- [ARCHITECTURE.md](ARCHITECTURE.md) - How the packages fit together and how to add a backend
- [CONTRIBUTING.md](CONTRIBUTING.md) - Development setup, testing, and PR process
- [SECURITY.md](SECURITY.md) - Supported versions, key handling, and per-backend considerations
- [CHANGELOG.md](CHANGELOG.md) - Release history across the workspace
- [docs/TOOL_RESPONSE_CHAT_LOOP.md](docs/TOOL_RESPONSE_CHAT_LOOP.md) - How a tool call round-trips through the stream
- [docs/concurrent-send-stall.md](docs/concurrent-send-stall.md) - Investigation behind the shared HTTP client's write gate

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
