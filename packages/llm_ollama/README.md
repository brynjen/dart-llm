# llm_ollama

[![pub.dev](https://img.shields.io/pub/v/llm_ollama)](https://pub.dev/packages/llm_ollama)

Ollama backend implementation for LLM interactions in Dart.

Available on [pub.dev](https://pub.dev/packages/llm_ollama).

Part of the [dart-llm](https://github.com/brynjen/dart-llm) ecosystem.

## Features

- Streaming chat responses
- Tool/function calling
- Vision (image) support
- Embeddings
- Thinking mode support
- Structured output (JSON mode and JSON Schema via the native `format` field)
- Model management (list, pull, show, version)
- Multi-instance pooling with health checks and per-model routing (`OllamaPool`)

## Streaming Reliability Guarantees

- NDJSON chunk-boundary-safe parsing: stream frames are buffered across transport chunks and parsed only when newline-terminated
- Bounded malformed-line retries: parser tolerates up to 3 consecutive malformed non-empty lines
- Explicit failure on persistent corruption: parser throws `LLMApiException` after retry budget exhaustion (no silent infinite dropping)

## Installation

```yaml
dependencies:
  llm_ollama: ^0.3.2
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

Ollama's `think` field accepts a bool or a level string, and has **no numeric
token budget**. `llm_ollama` sends:

| Options | wire `think` |
|---|---|
| `think: false` | `false` |
| `think: true`, no knobs | `true` (bool — keeps bool-only models working) |
| `think: true, reasoningEffort: none` | `false` |
| `minimal` / `low` | `"low"` |
| `medium` | `"medium"` |
| `high` / `xhigh` | `"high"` |
| `max` | `"max"` |
| `think: true, reasoningBudget: N` | level derived via `reasoningEffortForBudget` |

An explicit `reasoningEffort` wins over `reasoningBudget`, and
`backendOptions['think']` overrides everything. Note that some models accept
only bools (level strings error server-side) while gpt-oss ignores bools and
requires a level — levels are therefore only sent when you explicitly set one
of the knobs.

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
final modelRepo = OllamaRepository();
final supportsSchema = await modelRepo.supportsStructuredOutput('llama3.2');

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

## Capabilities

`capabilitiesForModel` reports what the backend implements. To find out what a
*specific model* supports, ask the server:

```dart
final repo = OllamaRepository(baseUrl: 'http://localhost:11434');

if (await repo.supportsVision('llama3.2-vision')) { /* attach images */ }
if (await repo.supportsStructuredOutput('qwen3:0.6b')) { /* pass a schema */ }
```

`streamChat` runs the vision check for you: passing images to a model whose
`/api/show` capabilities do not include vision throws
`VisionNotSupportedException` before any request is sent.

## Pool

Route across several Ollama servers — useful when models are pinned to specific
GPUs:

```dart
final pool = OllamaPool(
  instances: [
    OllamaInstanceConfig(
      baseUrl: 'http://bigcard:11434',
      maxConcurrent: 1,
      exclusiveModels: ['llama3.3:70b'],
      embeddingIsolation: EmbeddingIsolation.unloadFirst,
    ),
    OllamaInstanceConfig(
      baseUrl: 'http://smallcard:11434',
      maxConcurrent: 3,
      preferredModels: ['qwen3:0.6b'],
    ),
  ],
  modelConfigs: [
    OllamaModelConfig(pattern: 'llama3.3:*', maxConcurrent: 1),
  ],
  healthCheck: const HealthCheckConfig(),
);

final stream = pool.streamChat('qwen3:0.6b', messages: messages);
```

`OllamaPool` is a drop-in `LLMChatRepository` with routing, per-instance
concurrency limits, optional per-model limits (`pattern` supports `*` globs),
queue limits, and `/api/version` health checks. Unhealthy instances are excluded
from routing until they recover.

`EmbeddingIsolation` addresses the VRAM problem specific to Ollama: an instance
serving one large chat model has to swap it out to run an embedding model.
`unloadFirst` injects `keep_alive: '0'` so the embedding model is released
immediately; `dedicated` routes every `embed` call to an instance tagged
`preferEmbedding`.

Inspect live state with `pool.stats()`, which returns an `OllamaPoolStats`
carrying per-instance health, in-flight and queued counts. A pool that cannot
place a request throws `OllamaNoEligibleInstanceException`,
`OllamaQueueFullException` or `OllamaQueueTimeoutException`. There is also a
fluent `OllamaPool.builder()`.

## Resource cleanup

Every repository owns an HTTP client unless you pass one in; whoever creates the
client closes it.

```dart
final repo = OllamaChatRepository(baseUrl: 'http://localhost:11434');
// ... use it ...
repo.close();

final pool = OllamaPool(instances: [...]);
// ... use it ...
pool.dispose();   // stops health checks and closes owned per-instance clients
```

A client you supply is never closed for you.

## Notes

- **Retries are off by default.** Pass a `RetryConfig` to enable them.
- **`batchEmbed` does not batch.** Ollama's `/api/embed` takes one input at a
  time, so `batchEmbed` delegates to `embed`. It exists for interface parity.
- Portable `LLMChatOptions` fields (`temperature`, `topP`, `topK`,
  `maxOutputTokens`, `stopSequences`) are mapped into Ollama's nested
  `options` object for you — you only need raw `backendOptions['options']` for
  knobs without a portable equivalent.

## Testing

```bash
dart test --exclude-tags integration

OLLAMA_BASE_URL=http://localhost:11434 dart test --tags integration
```

Integration tests read `OLLAMA_BASE_URL` from the environment or a local `.env`
(see `.env.example`). They need the models named in
`test/integration/test_helpers.dart` pulled on the target server.
