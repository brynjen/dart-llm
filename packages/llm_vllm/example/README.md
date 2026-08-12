# llm_vllm examples

## CLI

```bash
dart run example/cli_example.dart
dart run example/cli_example.dart Qwen/Qwen3-0.6B
dart run example/cli_example.dart Qwen/Qwen3-0.6B http://localhost:8000
```

If your vLLM server was started with `--api-key`, pass the key as the third
argument or set `VLLM_API_KEY`.

## Minimal Usage

```dart
import 'package:llm_vllm/llm_vllm.dart';

final repo = VLLMChatRepository(baseUrl: 'http://localhost:8000');

final stream = repo.streamChat('Qwen/Qwen3-0.6B', messages: [
  LLMMessage(role: LLMRole.user, content: 'Hello!'),
]);

await for (final chunk in stream) {
  print(chunk.message?.content ?? '');
}
```

## Model Listing

```dart
final vllmRepo = VLLMRepository(baseUrl: 'http://localhost:8000');
final models = await vllmRepo.models();
```

## Integration Environment

```bash
export VLLM_BASE_URL=http://localhost:8000
export VLLM_CHAT_MODEL=Qwen/Qwen3-0.6B
export VLLM_EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
export VLLM_API_KEY=optional-key
```
