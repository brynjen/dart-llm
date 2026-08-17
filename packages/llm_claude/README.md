# llm_claude

[![pub.dev](https://img.shields.io/pub/v/llm_claude)](https://pub.dev/packages/llm_claude)

Anthropic Claude backend for LLM interactions in Dart. Part of the [dart-llm](https://github.com/brynjen/dart-llm) ecosystem.

Available on [pub.dev](https://pub.dev/packages/llm_claude).

## Features

- Streaming chat responses via the Anthropic Messages API
- Tool/function calling with automatic multi-turn tool-loop execution
- Thinking mode (extended reasoning) support
- Structured output via system-message injection (`JsonFormat`, `JsonSchemaFormat`)
- Builder pattern for fluent configuration
- Configurable retry and timeout policies

## Installation

```yaml
dependencies:
  llm_claude: ^0.2.0
```

## Prerequisites

You need an Anthropic API key. Get one from [console.anthropic.com](https://console.anthropic.com/).

**Important**: Never commit your API key to version control. Use environment variables or a `.env` file.

## Usage

### Basic Chat

```dart
import 'package:llm_claude/llm_claude.dart';

final repo = ClaudeChatRepository(apiKey: 'your-api-key');

final stream = repo.streamChat('claude-haiku-4-5-20251001', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  stdout.write(chunk.message?.content ?? '');
}
```

### System Message

```dart
final stream = repo.streamChat('claude-haiku-4-5-20251001', messages: [
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
  'claude-haiku-4-5-20251001',
  messages: [LLMMessage(role: LLMRole.user, content: 'What is the weather in Oslo?')],
  tools: [WeatherTool()],
);
```

### Structured Output

Claude has no native `response_format` parameter, so structured output is implemented by injecting a schema instruction into the system field — appended after any user-defined system content.

```dart
import 'package:llm_core/llm_core.dart';

// Simple JSON mode
final stream = repo.streamChat(
  'claude-haiku-4-5-20251001',
  messages: [LLMMessage(role: LLMRole.user, content: 'List three fruits as JSON.')],
  options: const LLMChatOptions(responseFormat: JsonFormat()),
);

// JSON Schema mode
const schema = {
  'type': 'object',
  'properties': {
    'name': {'type': 'string'},
    'age': {'type': 'integer'},
  },
  'required': ['name', 'age'],
};

final stream = repo.streamChat(
  'claude-haiku-4-5-20251001',
  messages: [LLMMessage(role: LLMRole.user, content: 'Return a person object.')],
  options: const LLMChatOptions(
    responseFormat: JsonSchemaFormat(name: 'Person', schema: schema),
  ),
);
```

### Thinking Mode

Extended reasoning (thinking) is supported on compatible models:

```dart
final stream = repo.streamChat(
  'claude-haiku-4-5-20251001',
  messages: [LLMMessage(role: LLMRole.user, content: 'Solve this step by step: ...')],
  think: true,
  options: const LLMChatOptions(
    backendOptions: {'thinking_budget': 16000},
  ),
);

await for (final chunk in stream) {
  if (chunk.message?.thinking != null) {
    // Extended reasoning content
    stdout.write(chunk.message!.thinking!);
  } else {
    stdout.write(chunk.message?.content ?? '');
  }
}
```

### Non-Streaming Response

```dart
final response = await repo.chatResponse('claude-haiku-4-5-20251001', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

print(response.content);
```

### Using LLMChatOptions

```dart
final options = LLMChatOptions(
  tools: [WeatherTool()],
  toolAttempts: 5,
  backendOptions: {
    'max_tokens': 8192,
    'thinking_budget': 10000,
  },
);

final stream = repo.streamChat('claude-haiku-4-5-20251001', messages: messages, options: options);
```

## Advanced Configuration

### Builder Pattern

```dart
final repo = ClaudeChatRepository.builder()
  .apiKey('your-api-key')
  .baseUrl('https://api.anthropic.com')
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
final repo = ClaudeChatRepository(
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
final repo = ClaudeChatRepository(
  apiKey: 'your-api-key',
  timeoutConfig: TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 5),
    totalTimeout: Duration(minutes: 10),
  ),
);
```

## Models

See [Anthropic Models](https://docs.anthropic.com/en/docs/about-claude/models) for available models:

- `claude-haiku-4-5-20251001` — Low-cost current Haiku model used by live tests
- `claude-opus-5` — Most capable
- `claude-sonnet-5` — Balanced performance and cost
- `claude-haiku-4-5` — Fastest and cheapest

Model families differ in the request shape they accept, and `llm_claude`
selects it automatically from the model id:

| Model family | Thinking | `temperature` / `top_p` / `top_k` | Structured output |
|---|---|---|---|
| Opus 4.7+, Sonnet 5, Fable 5, Mythos 5 | `adaptive` | **rejected (400)** — omitted automatically | native `output_config` |
| Opus 4.6, Sonnet 4.6 | `adaptive` | accepted | native `output_config` |
| Opus 4.5 and earlier, Haiku 4.5, Claude 3 | `budget_tokens` | accepted | system-prompt injection |

Sending `budget_tokens` to a current model — or a sampling parameter to Opus
4.7+ — is a `400`, not a warning. `LLMChatOptions.reasoningBudget` is
translated to an `output_config.effort` level on models that no longer accept
token budgets, so the setting is honored rather than dropped.

On current models an explicit `LLMChatOptions.reasoningEffort` wins over a
budget-derived level (effort-native path); on legacy models the budget wins,
and an effort-only request converts through `claudeBudgetForEffort`
(budget-native path).

An unrecognized model id is treated as a current model, so a newly released
Claude works without a library update.

## Notes

- Claude does not support embeddings. `embed()` and `batchEmbed()` throw `UnsupportedError`.
- Structured output is implemented via system-message injection (no native `response_format` API).
- `max_tokens` defaults to 4096; override via `backendOptions['max_tokens']`.
