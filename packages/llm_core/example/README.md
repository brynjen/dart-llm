# llm_core examples

`llm_core` has no backend of its own — it defines the abstractions every
backend implements. Install it alongside a backend package
(`llm_ollama`, `llm_vllm`, `llm_chatgpt`, `llm_claude`, `llm_gemini`,
`llm_llamacpp`) and program against `LLMChatRepository`.

See `provider_agnostic_example.dart` for a runnable example.

## Programming against the interface

```dart
import 'package:llm_core/llm_core.dart';

Future<String> summarize(LLMChatRepository repo, String model, String text) async {
  final response = await repo.chatResponse(model, messages: [
    LLMMessage(role: LLMRole.user, content: 'Summarize:\n\n$text'),
  ]);
  return response.content;
}
```

Any backend can be passed in, so swapping providers is a one-line change at the
composition root.

## Shared options

`LLMChatOptions` carries generation, reasoning, tool, structured-output,
timeout, retry, cache and metrics settings. Each backend maps them onto its own
wire format, and drops or translates what its API does not accept:

```dart
const options = LLMChatOptions(
  temperature: 0.2,
  maxOutputTokens: 512,
  think: true,
  responseFormat: JsonFormat(),
);
```

## Finish reasons

Always check `finishReason` before treating a response as valid output —
`LLMFinishReason.refusal` in particular arrives as a *successful* response with
empty or partial content:

```dart
switch (response.finishReason) {
  case LLMFinishReason.refusal:
    // Provider safety classifiers declined the request.
  case LLMFinishReason.length:
    // Truncated — raise maxOutputTokens.
  case LLMFinishReason.contentFilter:
    // Output was filtered.
  default:
    // Use response.content.
}
```
