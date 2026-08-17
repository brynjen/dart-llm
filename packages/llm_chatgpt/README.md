# llm_chatgpt

[![pub.dev](https://img.shields.io/pub/v/llm_chatgpt)](https://pub.dev/packages/llm_chatgpt)

OpenAI/ChatGPT backend implementation for LLM interactions in Dart.

Available on [pub.dev](https://pub.dev/packages/llm_chatgpt).

## Features

- Streaming chat responses
- Tool/function calling
- Embeddings
- Compatible with Azure OpenAI

## Installation

```yaml
dependencies:
  llm_chatgpt: ^0.2.0
```

## Prerequisites

You need an OpenAI API key. Get one from [platform.openai.com](https://platform.openai.com/).

**Important**: Never commit your API key to version control. Use environment variables or a `.env` file.

## Usage

### Basic Chat

```dart
import 'package:llm_chatgpt/llm_chatgpt.dart';

final repo = ChatGPTChatRepository(apiKey: 'your-api-key');

final stream = repo.streamChat('gpt-5.4-nano', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  print(chunk.message?.content ?? '');
}
```

### Tool Calling

```dart
final stream = repo.streamChat('gpt-5.4-nano',
  messages: messages,
  tools: [MyTool()],
);
```

### Structured Output

Use `LLMChatOptions.responseFormat` to enforce JSON output natively via the OpenAI `response_format` API:

```dart
import 'package:llm_core/llm_core.dart';

// Simple JSON mode
final stream = repo.streamChat(
  'gpt-5.4-nano',
  messages: [LLMMessage(role: LLMRole.user, content: 'List three fruits as JSON.')],
  options: const LLMChatOptions(responseFormat: JsonFormat()),
);

// JSON Schema mode (strict schema enforcement)
const schema = {
  'type': 'object',
  'properties': {
    'name': {'type': 'string'},
    'age': {'type': 'integer'},
  },
  'required': ['name', 'age'],
  'additionalProperties': false,
};

final stream = repo.streamChat(
  'gpt-5.4-nano',
  messages: [LLMMessage(role: LLMRole.user, content: 'Return a person object.')],
  options: const LLMChatOptions(
    responseFormat: JsonSchemaFormat(name: 'Person', schema: schema),
  ),
);
```

### Embeddings

```dart
final embeddings = await repo.embed(
  model: 'text-embedding-3-small',
  messages: ['Hello world', 'Goodbye world'],
);
```

### Non-Streaming Response

Get a complete response without streaming:

```dart
final response = await repo.chatResponse('gpt-5.4-nano', messages: [
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
  tools: [MyTool()],
  toolAttempts: 5,
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
);

final stream = repo.streamChat('gpt-5.4-nano', messages: messages, options: options);
```

### Reasoning models

Reasoning models (o-series, gpt-5 family) are detected by model id
(`gptIsReasoningModel`) and handled differently from conventional models:

- `temperature` / `top_p` are **dropped** on reasoning models — the API
  rejects them with a `400`.
- `reasoningEffort` maps to `reasoning_effort`, clamped to what the family
  accepts (`gptEffortWireValue`): o-series `low`/`medium`/`high`; gpt-5
  `minimal`/`low`/`medium`/`high`; gpt-5.1+ `none`/`low`/`medium`/`high`
  (plus `xhigh` on codex-max ids). Never sent to conventional models or to
  `o1-mini`/`o1-preview`, which predate the parameter.
- OpenAI has **no exact reasoning-token budget**, so `reasoningBudget` is
  honored as a derived effort level (an explicit `reasoningEffort` wins).
- Reasoning models always reason, so the knobs apply regardless of `think`.
- Streaming requests set `stream_options: {include_usage: true}`;
  reasoning-token usage surfaces as `LLMUsage.reasoningTokens` from
  `completion_tokens_details.reasoning_tokens`.

```dart
final options = LLMChatOptions(reasoningEffort: ReasoningEffort.high);
final stream = repo.streamChat('gpt-5.4', messages: messages, options: options);
```

### Using with Azure OpenAI

```dart
final repo = ChatGPTChatRepository(
  apiKey: 'your-azure-api-key',
  baseUrl: 'https://your-resource.openai.azure.com',
);
```

## Advanced Configuration

### Builder Pattern

Use the builder for complex configurations:

```dart
import 'package:llm_core/llm_core.dart';

// Standard OpenAI
final repo = ChatGPTChatRepository.builder()
  .apiKey('your-api-key')
  .baseUrl('https://api.openai.com')
  .maxToolAttempts(10)
  .retryConfig(RetryConfig(
    maxAttempts: 5,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
  ))
  .timeoutConfig(TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 5),
    totalTimeout: Duration(minutes: 10),
  ))
  .build();

// Azure OpenAI
final azureRepo = ChatGPTChatRepository.builder()
  .apiKey('your-azure-api-key')
  .baseUrl('https://your-resource.openai.azure.com')
  .maxToolAttempts(10)
  .retryConfig(RetryConfig(maxAttempts: 3))
  .timeoutConfig(TimeoutConfig(readTimeout: Duration(minutes: 5)))
  .build();
```

### Retry Configuration

Configure automatic retries for failed requests:

```dart
import 'package:llm_core/llm_core.dart';

final repo = ChatGPTChatRepository(
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

Configure timeouts for different scenarios:

```dart
import 'package:llm_core/llm_core.dart';

final repo = ChatGPTChatRepository(
  apiKey: 'your-api-key',
  timeoutConfig: TimeoutConfig(
    connectionTimeout: Duration(seconds: 10),
    readTimeout: Duration(minutes: 5),
    totalTimeout: Duration(minutes: 10),
  ),
);
```

## Models

See [OpenAI Models](https://platform.openai.com/docs/models) for available models:

- `gpt-5.4-nano` - Low-cost current-generation chat model used by live tests
- `gpt-5.4-mini` - Larger current-generation small model
- `gpt-5.4` - More capable current-generation model
- `text-embedding-3-small` - Low-cost embeddings used by live tests
- `text-embedding-3-large` - Higher quality embeddings
