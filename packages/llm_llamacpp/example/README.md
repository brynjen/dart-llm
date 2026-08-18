# llm_llamacpp Examples

## Prerequisites

1. **GGUF Model**: Download a model in GGUF format from [Hugging Face](https://huggingface.co/models?search=gguf)
   
   Recommended small models for testing:
   - `qwen2-0.5b-instruct-q4_k_m.gguf` (~400MB)
   - `tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf` (~700MB)
   - `phi-2.Q4_K_M.gguf` (~1.6GB)

2. **Native library**: nothing to do. `hook/build.dart` downloads a prebuilt
   bundle (or builds from the vendored submodule) during `dart pub get`. For a
   pure-Dart run the loader may need pointing at the hook's output — see
   [Troubleshooting](#library-not-found).

## CLI Example

A simple command-line chat interface:

```bash
cd packages/llm_llamacpp
dart run example/cli_example.dart /path/to/your/model.gguf
```

## Using in Your Own Code

### Basic Usage

`LlamaCppRepository` owns model management; `LlamaCppChatRepository` chats.

```dart
import 'package:llm_llamacpp/llm_llamacpp.dart';

Future<void> main() async {
  const modelPath = '/path/to/model.gguf';
  final modelRepo = LlamaCppRepository();

  try {
    final model = await modelRepo.loadModel(modelPath);

    final chatRepo = LlamaCppChatRepository.withModel(
      model,
      modelRepo.bindings,
      contextSize: 2048,
      nGpuLayers: 0, // Increase for GPU acceleration
    );

    try {
      final stream = chatRepo.streamChat(modelPath, messages: [
        LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
        LLMMessage(role: LLMRole.user, content: 'Hello!'),
      ]);

      await for (final chunk in stream) {
        print(chunk.message?.content ?? '');
      }
    } finally {
      chatRepo.dispose();
    }
  } finally {
    modelRepo.dispose();
  }
}
```

### Chat templates

Nothing to configure — the GGUF's own chat template is applied by llama.cpp. The
template classes this package once exposed were removed in 0.1.5.

### GPU Acceleration

```dart
final model = await modelRepo.loadModel(
  modelPath,
  options: const ModelLoadOptions(nGpuLayers: 35),
);

final chatRepo = LlamaCppChatRepository.withModel(
  model,
  modelRepo.bindings,
  nGpuLayers: 35, // Offload 35 layers to GPU
);
```

## Supported Platforms

| Platform | Architecture | Status |
|----------|--------------|--------|
| Linux    | x86_64       | ✅     |
| macOS    | arm64/x86_64 | ✅     |
| Windows  | x86_64       | ✅     |
| Android  | arm64-v8a    | ✅     |
| Android  | x86_64       | ✅     |
| iOS      | arm64        | ✅     |

## Troubleshooting

### Library not found

For a pure-Dart run, point the loader at the build hook's output:

```bash
export LLM_LLAMACPP_LIB_DIR=$(dirname $(find .dart_tool/hooks_runner \
  \( -name 'libllama.*' -o -name 'llama.dll' \) | head -1))
```

Without the override the loader also checks the current working directory, next
to the executable, and the system library path. Under Flutter the library is
bundled in the app and no override is needed.

### Model loading fails

- Ensure the model file is a valid GGUF format
- Check you have enough RAM for the model
- Try a smaller quantized model (Q4_K_M is a good balance)

### Slow inference

- Enable GPU acceleration with `nGpuLayers`
- Use a smaller model
- Reduce context size
- Use a more aggressively quantized model (Q4_0, Q4_1)

