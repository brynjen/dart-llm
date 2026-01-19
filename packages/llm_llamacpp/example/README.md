# llm_llamacpp Examples

## Prerequisites

1. **GGUF Model**: Download a model in GGUF format from [Hugging Face](https://huggingface.co/models?search=gguf)
   
   Recommended small models for testing:
   - `qwen2-0.5b-instruct-q4_k_m.gguf` (~400MB)
   - `tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf` (~700MB)
   - `phi-2.Q4_K_M.gguf` (~1.6GB)

2. **Native Library**: The llama.cpp shared library must be available:
   - Run the GitHub Actions workflow to build libraries
   - Or build llama.cpp manually and place the library in your path

## CLI Example

A simple command-line chat interface:

```bash
cd packages/llm_llamacpp
dart run example/cli_example.dart /path/to/your/model.gguf
```

## Using in Your Own Code

### Basic Usage

```dart
import 'package:llm_llamacpp/llm_llamacpp.dart';

Future<void> main() async {
  final repo = LlamaCppChatRepository(
    contextSize: 2048,
    nGpuLayers: 0, // Increase for GPU acceleration
  );

  try {
    // Load model
    await repo.loadModel('/path/to/model.gguf');

    // Chat
    final stream = repo.streamChat('model', messages: [
      LLMMessage(role: LLMRole.system, content: 'You are helpful.'),
      LLMMessage(role: LLMRole.user, content: 'Hello!'),
    ]);

    await for (final chunk in stream) {
      print(chunk.message?.content ?? '');
    }
  } finally {
    repo.dispose();
  }
}
```

### Custom Prompt Templates

```dart
// Use a specific template
repo.template = Llama3Template();

// Or let it auto-detect from model name
repo.template = getTemplateForModel('llama-3-8b');
```

### GPU Acceleration

```dart
final repo = LlamaCppChatRepository(
  nGpuLayers: 35, // Offload 35 layers to GPU
);

await repo.loadModel('/path/to/model.gguf', options: ModelLoadOptions(
  nGpuLayers: 35,
));
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

Make sure the native library is in one of these locations:
- Current working directory
- Next to your executable
- System library path (`/usr/local/lib`, etc.)

### Model loading fails

- Ensure the model file is a valid GGUF format
- Check you have enough RAM for the model
- Try a smaller quantized model (Q4_K_M is a good balance)

### Slow inference

- Enable GPU acceleration with `nGpuLayers`
- Use a smaller model
- Reduce context size
- Use a more aggressively quantized model (Q4_0, Q4_1)

