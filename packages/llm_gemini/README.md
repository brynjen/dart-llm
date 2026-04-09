# llm_gemini

[![pub.dev](https://img.shields.io/pub/v/llm_gemini)](https://pub.dev/packages/llm_gemini)

Google Gemini backend for LLM interactions in Dart. Part of the [dart-llm](https://github.com/brynjen/dart-llm) ecosystem.

Available on [pub.dev](https://pub.dev/packages/llm_gemini).

## Features

- Streaming chat responses via the Gemini API
- Tool/function calling with automatic multi-turn tool-loop execution
- Thinking mode support
- Native structured output via `generationConfig` (`JsonFormat`, `JsonSchemaFormat`)
- Embeddings (single and batch)
- Builder pattern for fluent configuration
- Configurable retry and timeout policies

## Installation

```yaml
dependencies:
  llm_gemini: ^0.2.0
```

## Prerequisites

You need a Google API key with Gemini API access. Get one from [aistudio.google.com](https://aistudio.google.com/).

**Important**: Never commit your API key to version control. Use environment variables or a `.env` file.

## Usage

### Basic Chat

```dart
import 'package:llm_gemini/llm_gemini.dart';

final repo = GeminiChatRepository(apiKey: 'your-api-key');

final stream = repo.streamChat('gemini-2.0-flash', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  stdout.write(chunk.message?.content ?? '');
}
```

### System Message

```dart
final stream = repo.streamChat('gemini-2.0-flash', messages: [
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
  'gemini-2.0-flash',
  messages: [LLMMessage(role: LLMRole.user, content: 'What is the weather in Oslo?')],
  tools: [WeatherTool()],
);
```

### Structured Output

Gemini supports native structured output via `generationConfig`. Use `JsonFormat` for any JSON, or `JsonSchemaFormat` to enforce a specific schema.

> **Note:** Gemini `responseSchema` uses UPPERCASE type names: `"STRING"`, `"INTEGER"`, `"OBJECT"`, `"ARRAY"`, etc. — not the lowercase JSON Schema standard used by OpenAI.

```dart
import 'package:llm_core/llm_core.dart';

// Simple JSON mode — any valid JSON output
final stream = repo.streamChat(
  'gemini-2.0-flash',
  messages: [LLMMessage(role: LLMRole.user, content: 'List three fruits as JSON.')],
  options: const StreamChatOptions(responseFormat: JsonFormat()),
);

// JSON Schema mode — enforces schema structure
const schema = {
  'type': 'OBJECT',
  'properties': {
    'name': {'type': 'STRING'},
    'age': {'type': 'INTEGER'},
  },
  'required': ['name', 'age'],
};

final stream = repo.streamChat(
  'gemini-2.0-flash',
  messages: [LLMMessage(role: LLMRole.user, content: 'Return a person object.')],
  options: const StreamChatOptions(
    responseFormat: JsonSchemaFormat(name: 'Person', schema: schema),
  ),
);
```

### Thinking Mode

Extended reasoning is supported on Gemini 2.x thinking models:

```dart
final stream = repo.streamChat(
  'gemini-2.0-flash-thinking-exp',
  messages: [LLMMessage(role: LLMRole.user, content: 'Solve this step by step: ...')],
  think: true,
  options: const StreamChatOptions(
    backendOptions: {'thinking_budget': 8192},
  ),
);
```

### Embeddings

```dart
// Single text
final embeddings = await repo.embed(
  model: 'text-embedding-004',
  messages: ['Hello world'],
);
print(embeddings.first.embedding); // List<double>

// Batch (uses batchEmbedContents endpoint)
final batchEmbeddings = await repo.batchEmbed(
  model: 'text-embedding-004',
  messages: ['Hello world', 'Goodbye world'],
);
```

### Non-Streaming Response

```dart
final response = await repo.chatResponse('gemini-2.0-flash', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

print(response.content);
```

### Using StreamChatOptions

```dart
final options = StreamChatOptions(
  tools: [WeatherTool()],
  toolAttempts: 5,
  backendOptions: {
    'temperature': 0.7,
    'maxOutputTokens': 2048,
    'topP': 0.95,
  },
);

final stream = repo.streamChat('gemini-2.0-flash', messages: messages, options: options);
```

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

Pass any `generationConfig` fields directly:

```dart
final options = StreamChatOptions(
  backendOptions: {
    'temperature': 0.9,
    'topK': 40,
    'topP': 0.95,
    'maxOutputTokens': 4096,
    'stopSequences': ['END'],
  },
);
```

## Models

See [Gemini Models](https://ai.google.dev/gemini-api/docs/models/gemini) for available models:

- `gemini-2.0-flash` — Fast and capable, recommended default
- `gemini-2.0-pro` — Most capable
- `gemini-2.0-flash-thinking-exp` — Thinking/reasoning mode
- `text-embedding-004` — Text embeddings
