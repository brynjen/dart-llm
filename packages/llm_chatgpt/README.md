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
  llm_chatgpt:
    git:
      url: https://github.com/brynjen/dart-ollama.git
      path: packages/llm_chatgpt
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

### Using with Azure OpenAI

```dart
final repo = ChatGPTChatRepository(
  apiKey: 'your-azure-api-key',
  baseUrl: 'https://your-resource.openai.azure.com',
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

