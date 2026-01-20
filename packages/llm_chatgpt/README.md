# llm_chatgpt

OpenAI/ChatGPT backend implementation for LLM interactions in Dart.

## Features

- Streaming chat responses
- Tool/function calling
- Embeddings
- Compatible with Azure OpenAI

## Installation

```yaml
dependencies:
  llm_chatgpt: ^0.1.0
```

## Prerequisites

You need an OpenAI API key. Get one from [platform.openai.com](https://platform.openai.com/).

**Important**: Never commit your API key to version control. Use environment variables or a `.env` file.

## Usage

### Basic Chat

```dart
import 'package:llm_chatgpt/llm_chatgpt.dart';

final repo = ChatGPTChatRepository(apiKey: 'your-api-key');

final stream = repo.streamChat('gpt-4o', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  print(chunk.message?.content ?? '');
}
```

### Tool Calling

```dart
final stream = repo.streamChat('gpt-4o',
  messages: messages,
  tools: [MyTool()],
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
final response = await repo.chatResponse('gpt-4o', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

print(response.content);
print('Tokens: ${response.evalCount}');
```

### Using StreamChatOptions

Encapsulate all options in a single object:

```dart
import 'package:llm_core/llm_core.dart';

final options = StreamChatOptions(
  tools: [MyTool()],
  toolAttempts: 5,
  timeout: Duration(minutes: 5),
  retryConfig: RetryConfig(maxAttempts: 3),
);

final stream = repo.streamChat('gpt-4o', messages: messages, options: options);
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

- `gpt-4o` - Most capable model
- `gpt-4o-mini` - Smaller, faster, cheaper
- `gpt-4-turbo` - Previous generation
- `gpt-3.5-turbo` - Fast and cost-effective
- `text-embedding-3-small` - Embeddings
- `text-embedding-3-large` - Higher quality embeddings

