# llm_gemini examples

## CLI

```bash
export GEMINI_API_KEY=...
dart run example/cli_example.dart
dart run example/cli_example.dart gemini-3.5-flash
```

Prefix a message with `think:` to request thought summaries for that turn.

## Minimal usage

```dart
import 'dart:io';

import 'package:llm_gemini/llm_gemini.dart';

final repo = GeminiChatRepository(
  apiKey: Platform.environment['GEMINI_API_KEY']!,
);

final stream = repo.streamChat('gemini-3.5-flash-lite', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  stdout.write(chunk.message?.content ?? '');
}
```

Chat runs on the Interactions API (`POST /v1beta/interactions`), not the legacy
`generateContent` endpoint. The API key travels in the `x-goog-api-key` header,
never in the URL.

## Thinking

Thought summaries arrive on `chunk.message.thinking`, separate from the answer
text on `content`:

```dart
final stream = repo.streamChat(
  'gemini-3.5-flash-lite',
  messages: messages,
  think: true,
);

await for (final chunk in stream) {
  final thinking = chunk.message?.thinking;
  if (thinking != null) stdout.write('[$thinking]');
  stdout.write(chunk.message?.content ?? '');
}
```

`LLMChatOptions.reasoningEffort` and `reasoningBudget` are both mapped onto
Gemini's `thinking_level`; effort wins when both are set.

## Structured output

```dart
final stream = repo.streamChat(
  'gemini-3.5-flash-lite',
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

This sends a native `response_format` with the schema inline, so decoding is
constrained rather than merely requested.

## Embeddings

```dart
final embeddings = await repo.embed(
  model: 'gemini-embedding-001',
  messages: ['Hello, world!'],
);

// More than one input delegates to batchEmbed automatically.
final batch = await repo.batchEmbed(
  model: 'gemini-embedding-001',
  messages: ['first', 'second', 'third'],
);
```

## Backend options

`backendOptions` keys are snake_case, matching the wire format. A camelCase key
is not recognised as a generation-config field and ends up at the top level of
the request body:

```dart
const options = LLMChatOptions(
  backendOptions: {
    'temperature': 0.9,
    'max_output_tokens': 4096,
    'thinking_level': 'low',
  },
);
```

## Integration environment

```bash
export GEMINI_API_KEY=...
export GEMINI_CHAT_MODEL=gemini-3.5-flash-lite
export GEMINI_EMBEDDING_MODEL=gemini-embedding-001
```

The live tests are free-tier friendly but rate limited to 15 requests/minute —
run one file at a time.
