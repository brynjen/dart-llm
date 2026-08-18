# llm_core

[![pub.dev](https://img.shields.io/pub/v/llm_core)](https://pub.dev/packages/llm_core)

Core abstractions for LLM (Large Language Model) interactions in Dart.

Available on [pub.dev](https://pub.dev/packages/llm_core).

This package provides the foundational interfaces and models used by LLM backend implementations: `llm_ollama`, `llm_vllm`, `llm_chatgpt`, `llm_claude`, `llm_gemini`, and `llm_llamacpp`.

## Important: interfaces only

`llm_core` **does not connect to any LLM by itself**. It defines the shared types (messages, chunks, tools, options, etc.) and the `LLMChatRepository` interface.

To actually run chat/embeddings you must use a backend implementation, for example:

- `llm_ollama` (talks to a local/remote Ollama server)
- `llm_vllm` (talks to a self-hosted vLLM OpenAI-compatible server)
- `llm_chatgpt` (talks to OpenAI / ChatGPT-compatible APIs)
- `llm_claude` (talks to Anthropic Claude API)
- `llm_gemini` (talks to Google Gemini API)
- `llm_llamacpp` (runs local inference via llama.cpp)

## Installation

Most users should depend on a backend implementation (it re-exports `llm_core` types):

```yaml
dependencies:
  llm_ollama: ^0.3.2
```

If you're implementing your own backend, depend on `llm_core` directly:

```yaml
dependencies:
  llm_core: ^0.3.2
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

// Typed content parts are available for richer messages.
final multimodal = LLMMessage(
  role: LLMRole.user,
  contentParts: [
    LLMTextContent('Describe this image.'),
    LLMImageContent('https://example.com/image.png'),
  ],
);
```

### Repository Interface

Only `streamChat` is abstract. `capabilitiesForModel`, `chatResponse`,
`embed` and `batchEmbed` ship with working defaults — `chatResponse` collects
`streamChat` and drives the tool loop, `batchEmbed` falls back to `embed` — so a
new backend can start by implementing `streamChat` alone and override the rest
where the provider offers something better.

```dart
abstract class LLMChatRepository {
  // Abstract: the one member a backend must implement.
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options, // Optional: encapsulates all options
  });

  // What this model/deployment actually supports. Defaults to all-false;
  // backends override it.
  LLMCapabilities capabilitiesForModel(String model);

  Future<LLMResponse> chatResponse(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
  });

  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  });

  Future<List<LLMEmbedding>> batchEmbed({
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

### LLMChatOptions

Encapsulates all optional parameters for `streamChat()` to reduce parameter proliferation:

```dart
final options = LLMChatOptions(
  think: true,
  tools: [MyTool()],
  toolAttempts: 5,
  responseFormat: JsonSchemaFormat(name: 'Answer', schema: mySchema),
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
  recordMetrics: true,
);

final stream = repo.streamChat('model', messages: messages, options: options);
```

### Thinking / reasoning control

Reasoning is controlled by three fields on `LLMChatOptions`:

- **`think`** (bool) is the master switch. When `false` (the default), the two
  knobs below are ignored. Exception: OpenAI reasoning models always reason,
  so `llm_chatgpt` honors the knobs regardless of `think`.
- **`reasoningEffort`** (`ReasoningEffort?`) is the portable knob:
  `none`/`minimal`/`low`/`medium`/`high`/`xhigh`/`max` — the union of the
  provider scales. Backends clamp to the subset their API accepts. `null`
  sends nothing (provider default); `ReasoningEffort.none` actively suppresses
  thinking where the backend can express that.
- **`reasoningBudget`** (`int?`) is the exact-token knob, for backends with a
  native token budget (vLLM `thinking_token_budget`, legacy Claude
  `budget_tokens`). Backends without one (OpenAI, Ollama, Gemini) derive an
  effort level from it via `reasoningEffortForBudget()`.

Precedence when both knobs are set: effort wins on effort-native backends
(OpenAI, Ollama, modern Claude, Gemini); budget wins on budget-native paths
(vLLM, legacy Claude). Backend-specific `backendOptions` keys always beat
both. Reasoning-token usage, when the provider reports it, is surfaced as
`LLMUsage.reasoningTokens` (a subset of `completionTokens`).

```dart
// Portable: works against every backend, clamped to what each supports.
LLMChatOptions(think: true, reasoningEffort: ReasoningEffort.medium)

// Exact: a hard 512-token thinking cap on vLLM; derived medium-ish effort
// elsewhere.
LLMChatOptions(think: true, reasoningBudget: 512)
```

### Structured Output

`LLMResponseFormat` is a sealed class for controlling model output format. Each backend implements it according to its API capabilities:

```dart
// Simple JSON mode — model produces valid JSON
const options = LLMChatOptions(responseFormat: JsonFormat());

// JSON Schema mode — model output must conform to a schema
const options = LLMChatOptions(
  responseFormat: JsonSchemaFormat(
    name: 'Person',
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

Both are `const`-constructible and work with exhaustive `switch` pattern matching:

```dart
final instruction = switch (format) {
  JsonFormat() => 'Respond with JSON.',
  JsonSchemaFormat() => 'Respond with JSON matching: ${format.name}',
};
```

Backend behaviour:
| Backend | `JsonFormat` | `JsonSchemaFormat` |
|---|---|---|
| `llm_chatgpt` | `response_format: {type: "json_object"}` | `response_format: {type: "json_schema", ...}` with `strict` |
| `llm_vllm` | `response_format: {type: "json_object"}` | `response_format: {type: "json_schema", ...}`; also vLLM-native `structured_outputs` for regex / choice / grammar via `VLLMStructuredOutputs` |
| `llm_gemini` | `response_format` (Interactions API) | `response_format` with the schema inline |
| `llm_ollama` | `format: "json"` | `format: {schema}`; schema requires model support |
| `llm_claude` | system-message injection | native `output_config.format` on Opus 4.6+, Sonnet 4.6+, Fable 5 and Mythos 5; injection on older models |
| `llm_llamacpp` | system-message injection | system-message injection with schema |

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
  onRetry: (attempt, error, delay) => print('retry $attempt in $delay: $error'),
);
```

Passing `config: null` runs the operation exactly once. Only `llm_vllm` supplies
a default `RetryConfig` (a vLLM server answers `503` while loading weights); on
every other backend retries are off until you configure them.

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
// Every key is prefixed with the model id the request was made against:
const model = 'qwen3:0.6b';
print('Total requests: ${stats['$model.total_requests']}');
print('Successful: ${stats['$model.successful_requests']}');
print('Failed: ${stats['$model.failed_requests']}');
print('Avg latency: ${stats['$model.avg_latency_ms']}ms');
print('P95 latency: ${stats['$model.p95_latency_ms']}ms');
print('Total tokens: ${stats['$model.total_generated_tokens']}');

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
Validation.validateModelName('gpt-5.4-nano');

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

Every one implements `Exception` directly — there is no shared base, so catch
the specific type you care about.

- `ThinkingNotSupportedException` - Model doesn't support thinking
- `ToolsNotSupportedException` - Model doesn't support tools
- `VisionNotSupportedException` - Model doesn't support vision
- `ToolLoopIncompleteException` - `chatResponse` hit `maxToolAttempts` without a final answer
- `LLMApiException` - API request failed (carries `statusCode`)
- `ModelLoadException` - Model loading failed

`ThinkingNotAllowed`, `ToolsNotAllowed` and `VisionNotAllowed` remain as
deprecated aliases for the first three.

## Capabilities

Ask a repository what a model supports before sending a request that would
otherwise fail:

```dart
final caps = repo.capabilitiesForModel('qwen3:0.6b');
if (caps.thinking) { /* safe to pass think: true */ }
if (caps.tools) { /* safe to pass tools: [...] */ }
if (caps.vision) { /* safe to attach images */ }
```

Backends that can probe a live deployment do so — see
`VLLMRepository.resolveCapabilities()` and `OllamaRepository.supportsVision()`.

## HTTP Client

Every backend defaults to `createLLMHttpClient()`, which is worth knowing about
if you supply your own client:

```dart
final client = createLLMHttpClient(
  timeoutConfig: TimeoutConfig.defaultConfig,
  maxConnectionsPerHost: kLLMMaxConnectionsPerHost, // 64
  // Leave null for the platform default: kLLMMaxConcurrentWrites (4) on
  // macOS/iOS, unlimited elsewhere. Pass 0 to disable the gate outright.
  maxConcurrentWrites: null,
);

final repo = OllamaChatRepository(httpClient: client);
```

It bounds the connection pool per host, applies
`TimeoutConfig.connectionTimeout`, and drops the idle timeout to 3s so the
client retires idle connections before a server with a shorter keep-alive does
it mid-request. On macOS and iOS it wraps the client in `WriteGatedHttpClient`,
a counting semaphore that admits `kLLMMaxConcurrentWrites` (4) requests into
their connect+write phase at a time; other platforms are unlimited. This works around a Dart VM defect in the macOS
kqueue event handler where sockets opened and written in the same instant can
lose their writable event, leaving the request bytes unsent with no error.
Streaming *responses* are never gated. Pass `maxConcurrentWrites: 0` to disable.
Full investigation: `docs/concurrent-send-stall.md`.

On web, `createLLMHttpClient()` returns a plain `http.Client`.

## Cross-Cutting Concerns

All optional, all wired through any backend's builder or constructor:

- `RateLimiter` — client-side request pacing configuration (`maxRequests` per `windowDuration`, plus `burstSize`); `TokenBucketRateLimiter` is the implementation the repositories build from it
- `ResponseCache` / `MemoryResponseCache` — response caching keyed by
  `CacheKeyGenerator`, with `CacheStats`
- `LLMMetrics` / `DefaultLLMMetrics` — request counts, latency percentiles, tokens
- `LLMLogger` / `DefaultLLMLogger` — logging through `package:logging`; emits
  nothing until you subscribe to the `logging` stream
- `StreamToolExecutor` — the tool-execution loop `chatResponse` uses; call it
  directly if you drive the loop yourself
- `ChatRepositoryBuilderBase` — the shared builder surface every backend
  inherits: `.maxToolAttempts()` (default 90), `.retryConfig()`,
  `.timeoutConfig()`, `.rateLimiter()`, `.responseCache()`, `.metrics()`,
  `.httpClient()`

## Example

A provider-agnostic example lives in [example/](example/) — it programs against
`LLMChatRepository` so the same code runs on any backend.

## Usage with Backends

This package is typically used indirectly through backend packages:

```dart
import 'package:llm_ollama/llm_ollama.dart'; // Re-exports llm_core

final repo = OllamaChatRepository(baseUrl: 'http://localhost:11434');

final stream = repo.streamChat('qwen3:0.6b', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  print(chunk.message?.content ?? '');
}
```
