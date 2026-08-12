# llm_claude examples

## CLI

```bash
export ANTHROPIC_API_KEY=sk-ant-...
dart run example/cli_example.dart
dart run example/cli_example.dart claude-sonnet-5
```

## Minimal usage

```dart
import 'package:llm_claude/llm_claude.dart';

final repo = ClaudeChatRepository(apiKey: Platform.environment['ANTHROPIC_API_KEY']!);

final stream = repo.streamChat('claude-opus-5', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  stdout.write(chunk.message?.content ?? '');
}
```

## Thinking

`llm_claude` picks the thinking shape from the model id — adaptive on current
models, a token budget on older ones — so the same call works on both:

```dart
repo.streamChat(
  'claude-opus-5',
  messages: messages,
  options: const LLMChatOptions(think: true),
);
```

Thinking text arrives on `chunk.message.thinking`, separate from content.

## Structured output

```dart
repo.streamChat(
  'claude-opus-5',
  messages: messages,
  options: const LLMChatOptions(
    responseFormat: JsonSchemaFormat(
      name: 'person',
      schema: {
        'type': 'object',
        'properties': {'name': {'type': 'string'}},
        'required': ['name'],
      },
    ),
  ),
);
```

On models that support it this constrains decoding via `output_config`; older
models fall back to a system-prompt instruction.

## Integration environment

```bash
export ANTHROPIC_API_KEY=sk-ant-...
export ANTHROPIC_CHAT_MODEL=claude-haiku-4-5-20251001
```
