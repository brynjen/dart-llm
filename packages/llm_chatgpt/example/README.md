# llm_chatgpt Examples

## Prerequisites

1. **OpenAI API Key**: Get your API key from [platform.openai.com](https://platform.openai.com/api-keys)
2. **Internet Connection**: Required to connect to OpenAI API

## CLI Example

A simple command-line chat interface:

```bash
cd packages/llm_chatgpt
export OPENAI_API_KEY=your-api-key
dart run example/cli_example.dart
```

With custom model:

```bash
OPENAI_API_KEY=your-key dart run example/cli_example.dart gpt-4o
```

Or pass API key as argument:

```bash
dart run example/cli_example.dart gpt-4o-mini your-api-key
```

## Using in Your Own Code

### Basic Usage

```dart
import 'package:llm_chatgpt/llm_chatgpt.dart';

Future<void> main() async {
  final repo = ChatGPTChatRepository(apiKey: 'your-api-key');
  
  final stream = repo.streamChat('gpt-4o-mini', messages: [
    LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
    LLMMessage(role: LLMRole.user, content: 'Hello!'),
  ]);
  
  await for (final chunk in stream) {
    print(chunk.message?.content ?? '');
  }
}
```

### With Builder Pattern

```dart
final repo = ChatGPTChatRepository.builder()
  .apiKey('your-api-key')
  .baseUrl('https://api.openai.com') // Default
  .retryConfig(RetryConfig(maxAttempts: 3))
  .timeoutConfig(TimeoutConfig(readTimeout: Duration(minutes: 5)))
  .build();
```

### Azure OpenAI

```dart
final repo = ChatGPTChatRepository.builder()
  .apiKey('your-azure-api-key')
  .baseUrl('https://your-resource.openai.azure.com')
  .build();
```

### Non-Streaming Response

```dart
final response = await repo.chatResponse('gpt-4o-mini', messages: [
  LLMMessage(role: LLMRole.user, content: 'What is 2+2?'),
]);

print(response.content);
print('Tokens: ${response.evalCount}');
```

### Tool Calling

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
    // Evaluate expression...
    return result.toString();
  }
}

final stream = repo.streamChat(
  'gpt-4o-mini',
  messages: messages,
  tools: [CalculatorTool()],
);
```

### Embeddings

```dart
final embeddings = await repo.embed(
  'text-embedding-3-small',
  ['Hello, world!', 'How are you?'],
);

for (final embedding in embeddings) {
  print('Embedding: ${embedding.embedding.length} dimensions');
}
```

## Configuration

### Environment Variables

Set your API key via environment variable:

```bash
export OPENAI_API_KEY=your-api-key
dart run example/cli_example.dart
```

Or use `CHATGPT_ACCESS_TOKEN`:

```bash
export CHATGPT_ACCESS_TOKEN=your-token
dart run example/cli_example.dart
```

### Custom Base URL

For Azure OpenAI or custom endpoints:

```dart
final repo = ChatGPTChatRepository.builder()
  .apiKey('your-key')
  .baseUrl('https://your-resource.openai.azure.com')
  .build();
```

## Available Models

### Chat Models
- `gpt-4o` - Latest GPT-4 optimized model
- `gpt-4o-mini` - Faster, cheaper GPT-4 variant
- `gpt-4-turbo` - GPT-4 Turbo
- `gpt-3.5-turbo` - GPT-3.5 Turbo

### Embedding Models
- `text-embedding-3-small` - Small, fast embeddings
- `text-embedding-3-large` - Large, high-quality embeddings
- `text-embedding-ada-002` - Legacy embedding model

## Troubleshooting

### Invalid API key

- Verify your API key at [platform.openai.com](https://platform.openai.com/api-keys)
- Check for typos or extra spaces
- Ensure the key has the correct permissions

### Rate limit errors

- Implement retry logic with exponential backoff (built-in via `RetryConfig`)
- Use a model with higher rate limits
- Consider upgrading your OpenAI plan

### Network errors

- Check your internet connection
- Verify firewall/proxy settings
- Ensure OpenAI API is accessible from your network

### Azure OpenAI

- Use the correct base URL format: `https://<resource>.openai.azure.com`
- Ensure API version is compatible
- Check Azure resource permissions
