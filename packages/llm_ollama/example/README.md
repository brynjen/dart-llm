# llm_ollama Examples

## Prerequisites

1. **Ollama Installation**: Install and run Ollama locally
   - Download from [ollama.ai](https://ollama.ai)
   - Start the Ollama service (usually runs automatically)

2. **Model**: Pull a model using Ollama CLI
   ```bash
   ollama pull qwen2:0.5b
   # or
   ollama pull llama3:8b
   ```

## CLI Example

A simple command-line chat interface:

```bash
cd packages/llm_ollama
dart run example/cli_example.dart
```

With custom model and base URL:

```bash
dart run example/cli_example.dart qwen2:0.5b
dart run example/cli_example.dart llama3:8b http://localhost:11434
```

## Using in Your Own Code

### Basic Usage

```dart
import 'package:llm_ollama/llm_ollama.dart';

Future<void> main() async {
  final repo = OllamaChatRepository(baseUrl: 'http://localhost:11434');
  
  final stream = repo.streamChat('qwen2:0.5b', messages: [
    LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
    LLMMessage(role: LLMRole.user, content: 'Hello!'),
  ]);
  
  await for (final chunk in stream) {
    print(chunk.message?.content ?? '');
  }
}
```

### With Thinking Mode

```dart
final stream = repo.streamChat(
  'deepseek-r1:1.5b', // Thinking model
  messages: messages,
  think: true, // Enable thinking tokens
);

await for (final chunk in stream) {
  // Regular content
  print(chunk.message?.content ?? '');
  
  // Thinking/reasoning content
  if (chunk.message?.thinking != null) {
    print('[Thinking: ${chunk.message!.thinking}]');
  }
}
```

### With Builder Pattern

```dart
final repo = OllamaChatRepository.builder()
  .baseUrl('http://localhost:11434')
  .retryConfig(RetryConfig(maxAttempts: 3))
  .timeoutConfig(TimeoutConfig(readTimeout: Duration(minutes: 5)))
  .build();
```

### Model Management

```dart
final ollamaRepo = OllamaRepository(baseUrl: 'http://localhost:11434');

// List available models
final models = await ollamaRepo.listModels();
for (final model in models) {
  print('${model.name} - ${model.size} bytes');
}

// Pull a model
await ollamaRepo.pullModel('qwen2:0.5b');

// Show model info
final info = await ollamaRepo.showModel('qwen2:0.5b');
print('Modelfile: ${info.modelfile}');
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
  'qwen2:0.5b',
  messages: messages,
  tools: [CalculatorTool()],
);
```

## Configuration

### Environment Variables

You can configure the base URL via environment variable:

```bash
export OLLAMA_BASE_URL=http://localhost:11434
dart run example/cli_example.dart
```

### Custom Base URL

For remote Ollama instances:

```dart
final repo = OllamaChatRepository(
  baseUrl: 'http://your-ollama-server:11434',
);
```

## Troubleshooting

### Connection refused

- Make sure Ollama is running: `ollama serve`
- Check the base URL matches your Ollama instance
- Verify network connectivity

### Model not found

- Pull the model first: `ollama pull <model-name>`
- List available models: `ollama list`
- Check model name format (e.g., `qwen2:0.5b`)

### Slow responses

- Use a smaller/faster model
- Check Ollama server resources
- Consider using a local GPU-accelerated Ollama instance
