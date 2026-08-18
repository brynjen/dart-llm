# llm_gemini

[![pub.dev](https://img.shields.io/pub/v/llm_gemini)](https://pub.dev/packages/llm_gemini)

Google Gemini backend for LLM interactions in Dart. Part of the [dart-llm](https://github.com/brynjen/dart-llm) ecosystem.

Available on [pub.dev](https://pub.dev/packages/llm_gemini).

## Features

- Streaming chat responses via the Gemini **Interactions API** (`POST /v1beta/interactions`)
- Tool/function calling with automatic multi-turn tool-loop execution
- Thinking mode with thought summaries surfaced separately from content
- Native structured output via `response_format` (`JsonFormat`, `JsonSchemaFormat`)
- Vision input, plus generated images surfaced on `chunk.message.images`
- Embeddings (single and batch)
- Builder pattern for fluent configuration
- Configurable retry and timeout policies

### Interactions API

Chat runs on the Interactions API rather than the legacy `generateContent`
endpoint. What this changes for callers:

- The API key travels in the `x-goog-api-key` header, never as a `key=` query
  parameter, so it cannot leak into request logs or proxies.
- `streamChat` stays stateless: requests send `store: false` and serialize the
  whole conversation into the `input` array instead of chaining
  `previous_interaction_id`. Pass
  `backendOptions: {'previous_interaction_id': '…'}` to opt into server-side
  continuation.
- Thinking arrives as `thought_summary` deltas and populates
  `chunk.message.thinking`; ordinary text populates `chunk.message.content`.
- `chunk.providerMetadata` carries `interaction_id`, `thought_signatures`
  (keyed by step index), and the usage counters with no first-class slot:
  `total_tokens`, `total_thought_tokens`, `total_cached_tokens`,
  `total_tool_use_tokens`.
- Tool calls carry the server-provided call id.

Embeddings still use the `embedContent` / `batchEmbedContents` endpoints.

## Installation

```yaml
dependencies:
  llm_gemini: ^0.3.2
```

## Prerequisites

You need a Google API key with Gemini API access. Get one from [aistudio.google.com](https://aistudio.google.com/).

**Important**: Never commit your API key to version control. Use environment variables or a `.env` file.

## Usage

### Basic Chat

```dart
import 'package:llm_gemini/llm_gemini.dart';

final repo = GeminiChatRepository(apiKey: 'your-api-key');

final stream = repo.streamChat('gemini-3.5-flash-lite', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  stdout.write(chunk.message?.content ?? '');
}
```

### System Message

```dart
final stream = repo.streamChat('gemini-3.5-flash-lite', messages: [
  LLMMessage(role: LLMRole.system, content: 'You are a concise assistant.'),
  LLMMessage(role: LLMRole.user, content: 'Explain quantum entanglement.'),
]);
```

### Tool Calling

```dart
class WeatherTool extends LLMTool {
  @override
  String get name => 'get_weather';

  @override
  String get description => 'Get the current weather for a location.';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'location',
      type: 'string',
      description: 'City name',
      isRequired: true,
    ),
  ];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return {'temperature': 22, 'condition': 'sunny'};
  }
}

final stream = repo.streamChat(
  'gemini-3.5-flash-lite',
  messages: [LLMMessage(role: LLMRole.user, content: 'What is the weather in Oslo?')],
  tools: [WeatherTool()],
);
```

### Structured Output

Gemini supports native structured output via the `response_format` array. Use `JsonFormat` for any JSON, or `JsonSchemaFormat` to enforce a specific schema. Pass standard lowercase JSON Schema — unlike `generateContent`'s `responseSchema`, the Interactions API takes the schema as written.

```dart
import 'package:llm_core/llm_core.dart';

// Simple JSON mode — any valid JSON output
final stream = repo.streamChat(
  'gemini-3.5-flash-lite',
  messages: [LLMMessage(role: LLMRole.user, content: 'List three fruits as JSON.')],
  options: const LLMChatOptions(responseFormat: JsonFormat()),
);

// JSON Schema mode — enforces schema structure
const schema = {
  'type': 'object',
  'properties': {
    'name': {'type': 'string'},
    'age': {'type': 'integer'},
  },
  'required': ['name', 'age'],
};

final stream = repo.streamChat(
  'gemini-3.5-flash-lite',
  messages: [LLMMessage(role: LLMRole.user, content: 'Return a person object.')],
  options: const LLMChatOptions(
    responseFormat: JsonSchemaFormat(name: 'Person', schema: schema),
  ),
);
```

### Thinking Mode

Extended reasoning is supported on compatible Gemini models. `think: true` sends
`generation_config.thinking_summaries: "auto"`, and thought summaries arrive on
`chunk.message.thinking` rather than mixed into `chunk.message.content`.

```dart
final stream = repo.streamChat(
  'gemini-3.5-flash-lite',
  messages: [LLMMessage(role: LLMRole.user, content: 'Solve this step by step: ...')],
  think: true,
  options: const LLMChatOptions(
    reasoningBudget: 8192,
  ),
);

await for (final chunk in stream) {
  if (chunk.message?.thinking != null) stdout.write(chunk.message!.thinking!);
  if (chunk.message?.content != null) stdout.write(chunk.message!.content!);
}
```

The Interactions API has no raw thinking-token budget. `reasoningBudget` is
mapped onto the discrete `thinking_level` field with these thresholds:

| `reasoningBudget` | `thinking_level` |
|-------------------|------------------|
| `null`            | `medium`         |
| `<= 0`            | `minimal`        |
| `< 2048`          | `low`            |
| `< 8192`          | `medium`         |
| `>= 8192`         | `high`           |

An explicit `LLMChatOptions.reasoningEffort` wins over the budget mapping
(`none`/`minimal` → `minimal`, `low` → `low`, `medium` → `medium`,
`high`/`xhigh`/`max` → `high`), and
`backendOptions: {'thinking_level': 'high'}` bypasses both. Thought-token
usage is surfaced as `LLMUsage.reasoningTokens`.

### Embeddings

```dart
// Single text
final embeddings = await repo.embed(
  model: 'gemini-embedding-001',
  messages: ['Hello world'],
);
print(embeddings.first.embedding); // List<double>

// Batch (uses batchEmbedContents endpoint)
final batchEmbeddings = await repo.batchEmbed(
  model: 'gemini-embedding-001',
  messages: ['Hello world', 'Goodbye world'],
);
```

### Non-Streaming Response

```dart
final response = await repo.chatResponse('gemini-3.5-flash-lite', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

print(response.content);
```

### Using LLMChatOptions

```dart
final options = LLMChatOptions(
  tools: [WeatherTool()],
  toolAttempts: 5,
  // Portable fields are the easy path: `temperature` and `maxOutputTokens` are
  // mapped into generation_config for you.
  temperature: 0.7,
  maxOutputTokens: 2048,
);

final stream = repo.streamChat('gemini-3.5-flash-lite', messages: messages, options: options);
```

`backendOptions` keys are **snake_case**, matching the wire format. A camelCase
key such as `maxOutputTokens` is not recognised as a generation-config field and
is written to the top level of the request body instead — where the API either
rejects it or ignores it. See
[Generation Config via backendOptions](#generation-config-via-backendoptions).

## Advanced Configuration

### Builder Pattern

```dart
final repo = GeminiChatRepository.builder()
  .apiKey('your-api-key')
  .baseUrl('https://generativelanguage.googleapis.com')
  .maxToolAttempts(10)
  .retryConfig(RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
  ))
  .timeoutConfig(TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 5),
  ))
  .build();
```

### Retry Configuration

```dart
final repo = GeminiChatRepository(
  apiKey: 'your-api-key',
  retryConfig: RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    retryableStatusCodes: [429, 500, 502, 503, 504],
  ),
);
```

### Timeout Configuration

```dart
final repo = GeminiChatRepository(
  apiKey: 'your-api-key',
  timeoutConfig: TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 5),
    totalTimeout: Duration(minutes: 10),
  ),
);
```

### Generation Config via backendOptions

The Interactions API documents four `generation_config` fields: `temperature`,
`max_output_tokens`, `thinking_level`, and `thinking_summaries`. `temperature`
and `maxOutputTokens` from `LLMChatOptions` are mapped automatically. `topP`,
`topK`, and `stopSequences` have no documented Interactions equivalent and are
**not** sent.

Any documented field can be set directly, and `generation_config` is merged in
wholesale for anything else a model turns out to accept:

```dart
final options = LLMChatOptions(
  backendOptions: {
    'temperature': 0.9,
    'max_output_tokens': 4096,
    'thinking_level': 'low',
    // Escape hatch — merged into generation_config as-is.
    'generation_config': {'top_p': 0.95},
  },
);
```

Keys outside that set are written to the top level of the request body, so
undocumented request fields can be sent without a new release.

## Models

See [Gemini Models](https://ai.google.dev/gemini-api/docs/models/gemini) for available models:

- `gemini-3.6-flash` — Newest Flash model
- `gemini-3.5-flash` — Larger Flash model
- `gemini-3.5-flash-lite` — Low-cost current Gemini chat model used by live tests
- `gemini-embedding-001` — Embeddings used by live tests

## Notes

- `embed` with more than one input delegates to `batchEmbed`.
- `providerMetadata` carries `interaction_id`, `status`, `thought_signatures`,
  `total_tokens`, `total_thought_tokens`, `total_cached_tokens` and
  `total_tool_use_tokens`.
- Retries are off unless you pass a `RetryConfig`.

## Example

A runnable CLI lives in [example/](example/).
