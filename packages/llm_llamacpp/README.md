# llm_llamacpp

Local LLM inference via llama.cpp for Dart and Flutter.

## Features

- Local on-device inference with GGUF models
- Streaming token generation
- Multiple prompt templates (ChatML, Llama2, Llama3, Alpaca, Vicuna, Phi-3)
- Tool calling via prompt convention
- GPU acceleration support (CUDA, Metal, Vulkan)
- Cross-platform: Android, iOS, macOS, Windows, Linux
- Isolate-based inference (non-blocking UI)
- **Model management** - Discover, load, pool, and download models
- **GGUF metadata** - Read model info without loading

## Installation

```yaml
dependencies:
  llm_llamacpp:
    git:
      url: https://github.com/brynjen/dart-ollama.git
      path: packages/llm_llamacpp
```

## Prerequisites

### 1. GGUF Model

Download a model in GGUF format. **Important:** Use properly converted GGUF files from trusted sources.

### 2. Native Library

The llama.cpp shared library must be available:

**Option A**: Build from CI
- Run the GitHub Actions workflow `.github/workflows/build-llamacpp.yaml`
- Download artifacts and place in appropriate locations

**Option B**: Build manually
```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
mkdir build && cd build

# CPU only
cmake .. -DBUILD_SHARED_LIBS=ON

# With CUDA (NVIDIA GPU)
cmake .. -DBUILD_SHARED_LIBS=ON -DGGML_CUDA=ON

# With Metal (Apple Silicon)
cmake .. -DBUILD_SHARED_LIBS=ON -DGGML_METAL=ON

cmake --build . --config Release
```

## Model Compatibility

### ⚠️ Important: GGUF Source Matters

**Not all GGUF files are created equal.** Different converters include different metadata, and llama.cpp requires specific keys for certain architectures.

### Recommended Model Sources

| Source | Compatibility | Notes |
|--------|---------------|-------|
| [HuggingFace Official](https://huggingface.co) | ✅ Excellent | Models converted by the model authors (e.g., Qwen, Meta) |
| [Unsloth](https://huggingface.co/unsloth) | ✅ Excellent | High-quality conversions with imatrix quantization |
| [TheBloke](https://huggingface.co/TheBloke) | ✅ Good | Wide variety of models |
| [QuantFactory](https://huggingface.co/QuantFactory) | ✅ Good | Many model options |
| **Ollama model blobs** | ⚠️ Limited | May be missing required metadata (see below) |

### Ollama Models Compatibility

**Ollama stores models in `/root/.ollama/models/blobs/` (or `~/.ollama/`) as raw GGUF files.** However, Ollama's converter may not include all metadata that llama.cpp requires.

| Model Type | Ollama Blob | HuggingFace GGUF |
|------------|-------------|------------------|
| Standard LLMs (Llama, Mistral, Phi) | ✅ Works | ✅ Works |
| Qwen2/Qwen2.5 | ✅ Works | ✅ Works |
| **Qwen3-VL** (vision) | ❌ Missing `rope.dimension_sections` | ✅ Works |
| **Gemma3** (vision) | ❌ Missing `attention.layer_norm_rms_epsilon` | ✅ Works |
| Other vision models | ⚠️ May have issues | ✅ Recommended |

**If you encounter errors like:**
```
error loading model hyperparameters: key not found in model: <arch>.rope.dimension_sections
```

Download the model directly from HuggingFace instead of using Ollama's blob.

### Recommended Models

#### Small & Fast (< 1GB)
- [Qwen/Qwen2.5-0.5B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) (~400MB)

#### Balanced (1-5GB)
- [unsloth/Llama-3.2-1B-Instruct-GGUF](https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF) (~800MB)
- [unsloth/Phi-3.5-mini-instruct-GGUF](https://huggingface.co/unsloth/Phi-3.5-mini-instruct-GGUF) (~2GB)
- [unsloth/Qwen2.5-3B-Instruct-GGUF](https://huggingface.co/unsloth/Qwen2.5-3B-Instruct-GGUF) (~2GB)

#### High Quality (5-20GB)
- [unsloth/Llama-3.1-8B-Instruct-GGUF](https://huggingface.co/unsloth/Llama-3.1-8B-Instruct-GGUF) (~5GB Q4)
- [unsloth/Qwen2.5-14B-Instruct-GGUF](https://huggingface.co/unsloth/Qwen2.5-14B-Instruct-GGUF) (~9GB Q4)

#### Vision Models
- [unsloth/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF) (~5GB Q4)
- [Qwen/Qwen3-VL-4B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF) (~3GB Q4)

> **Note:** Vision model support is for text inference only. Image input requires additional multimodal bindings (not yet implemented).

## Usage

### Simplified Model Acquisition (getModel)

The easiest way to get models from HuggingFace - **deterministic, no guessing**:

```dart
import 'package:llm_llamacpp/llm_llamacpp.dart';

final repo = LlamaCppRepository();

// GGUF repo - auto-downloads Q4_K_M variant
final path = await repo.getModel(
  'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
  outputDir: '/models/',
);
print('Model ready: $path');

// Specific quantization
final path = await repo.getModel(
  'unsloth/Llama-3.2-1B-Instruct-GGUF',
  outputDir: '/models/',
  quantization: QuantizationType.q5_k_m,  // Q5_K_M variant
);

// Safetensors repo - MUST specify quantization
final path = await repo.getModel(
  'meta-llama/Llama-3.2-1B',
  outputDir: '/models/',
  quantization: QuantizationType.q4_k_m,  // Required for conversion
);

// Specific file (bypass matching)
final path = await repo.getModel(
  'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
  outputDir: '/models/',
  preferredFile: 'qwen2.5-0.5b-instruct-q8_0.gguf',
);

repo.dispose();
```

#### With Progress Updates

```dart
await for (final status in repo.getModelStream(
  'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
  outputDir: '/models/',
)) {
  print('${status.stage.name}: ${status.message}');
  if (status.progress != null) {
    print('  Progress: ${status.progressPercent}');
  }
  if (status.isComplete) {
    print('Ready: ${status.modelPath}');
  }
}
```

### Error Handling

The API is **deterministic** - it throws clear errors instead of guessing:

```dart
try {
  final path = await repo.getModel(
    'some/model-repo',
    outputDir: '/models/',
  );
} on ModelNotFoundException catch (e) {
  // No exact quantization match found
  // e.availableFiles lists what's available
  print(e);
  // "ModelNotFoundException: No Q4_K_M GGUF found in 'some/model-repo'.
  //  Available GGUF files:
  //    - model-q5_k_m.gguf (1.2 GB)
  //    - model-q8_0.gguf (2.1 GB)
  //  Specify file: getModel('some/model-repo', preferredFile: 'model-q5_k_m.gguf')"
  
} on AmbiguousModelException catch (e) {
  // Multiple files match the quantization
  // e.matchingFiles lists all matches
  print(e);
  // "AmbiguousModelException: Multiple Q4_K_M files found in 'some/model-repo':
  //    - model-q4_k_m.gguf
  //    - model-v2-q4_k_m.gguf
  //  Specify file: getModel('some/model-repo', preferredFile: 'model-v2-q4_k_m.gguf')"
  
} on ConversionRequiredException catch (e) {
  // Only safetensors, must specify quantization
  print(e);
  // "ConversionRequiredException: Quantization required for safetensors conversion.
  //  Repository: 'some/model-repo' only has safetensors (no GGUF).
  //  Example: getModel('some/model-repo', quantization: QuantizationType.q4_k_m)"
  
} on UnsupportedModelException catch (e) {
  // No GGUF or safetensors at all
  print(e);
}
```

### Model Management (LlamaCppRepository)

The `LlamaCppRepository` also provides discovery, loading/pooling, and low-level downloads:

```dart
import 'package:llm_llamacpp/llm_llamacpp.dart';

final repo = LlamaCppRepository();

// Discover models in a directory
final models = await repo.discoverModels('/path/to/models');
for (final model in models) {
  print('${model.name}: ${model.metadata?.sizeLabel} (${model.fileSizeLabel})');
}

// Read GGUF metadata without loading
final metadata = await GgufMetadata.fromFile('/path/to/model.gguf');
print('Architecture: ${metadata.architecture}');
print('Parameters: ${metadata.sizeLabel}');
print('Quantization: ${metadata.quantizationType}');
print('Context length: ${metadata.contextLength}');

// Load models with pooling (reference counting)
final model = await repo.loadModel('/path/to/model.gguf');
print('Loaded, ref count: ${repo.getModelRefCount(model.path)}');

// Load same model again (reuses existing, increments ref count)
final model2 = await repo.loadModel('/path/to/model.gguf');
print('Ref count now: ${repo.getModelRefCount(model.path)}'); // 2

// Unload (decrements ref count, disposes when 0)
repo.unloadModel('/path/to/model.gguf');

// Check system capabilities
for (final backend in repo.getAvailableBackends()) {
  print('${backend.name}: ${backend.isAvailable ? "✓" : "✗"} ${backend.deviceName ?? ""}');
}
print('Recommended GPU layers: ${repo.recommendedGpuLayers}');

// Low-level download (specific file)
await for (final progress in repo.downloadModel(
  'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
  'qwen2.5-0.5b-instruct-q4_k_m.gguf',
  '/path/to/models/',
)) {
  print('${progress.progressPercent} - ${progress.status}');
}

// Check what's available for a model
final plan = await repo.planModelAcquisition('Qwen/Qwen2.5-0.5B-Instruct');
print(plan); // "Download GGUF: ..." or "Convert safetensors → GGUF"

repo.dispose();
```

### Converting Safetensors to GGUF (Manual)

For manual conversion with full control:

```dart
final repo = LlamaCppRepository();

// Check if conversion is needed
final plan = await repo.planModelAcquisition('meta-llama/Llama-3.2-1B');
if (plan.method == AcquisitionMethod.convertFromSafetensors) {
  // Convert safetensors → GGUF with Q4_K_M quantization
  await for (final progress in repo.convertModel(
    repoId: 'meta-llama/Llama-3.2-1B',
    outputPath: '/path/to/llama-3.2-1b-q4.gguf',
    quantization: QuantizationType.q4_k_m,
    llamaCppPath: '/path/to/llama.cpp', // Optional, will auto-detect
  )) {
    print('${progress.stage}: ${progress.message}');
  }
}
```

**Requirements for conversion:**
- Python 3.8+ with: `pip install transformers torch safetensors sentencepiece`
- llama.cpp repository: `git clone https://github.com/ggerganov/llama.cpp`
- Build quantize tool: `cd llama.cpp && make llama-quantize`

**Available quantization types:**
| Type | Size | Quality | Use Case |
|------|------|---------|----------|
| `q4_k_m` | ~4.0x smaller | Good | **Recommended default** |
| `q5_k_m` | ~3.2x smaller | Better | Balanced quality/size |
| `q6_k` | ~2.7x smaller | High | Near-original quality |
| `q8_0` | ~2x smaller | Excellent | Minimal quality loss |
| `q3_k_m` | ~5.3x smaller | Lower | Memory constrained |
| `q2_k` | ~8x smaller | Lowest | Extreme compression |

### Basic Chat

```dart
import 'package:llm_llamacpp/llm_llamacpp.dart';

final repo = LlamaCppChatRepository(
  contextSize: 2048,
  nGpuLayers: 0, // Set > 0 for GPU acceleration
);

try {
  await repo.loadModel('/path/to/model.gguf');

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
```

### Custom Prompt Template

```dart
// Auto-detect from model name
repo.template = getTemplateForModel('llama-3-8b');

// Or set explicitly
repo.template = ChatMLTemplate();   // Qwen, many others
repo.template = Llama3Template();   // Llama 3.x
repo.template = Phi3Template();     // Phi-3
```

### GPU Acceleration

```dart
final repo = LlamaCppChatRepository(
  nGpuLayers: 99, // Offload all layers to GPU
);

await repo.loadModel('/path/to/model.gguf', options: ModelLoadOptions(
  nGpuLayers: 99,  // Use GPU for all layers
  useMemoryMap: true,
));
```

#### CUDA Setup (NVIDIA)

Requires CUDA toolkit 12.4+ for modern GPUs:

```bash
# Ubuntu/Debian
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get install cuda-toolkit-12-8

# Set environment
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```

### Tool Calling

Tool calling is implemented via prompt convention (the model outputs JSON):

```dart
final stream = repo.streamChat('model',
  messages: [
    LLMMessage(
      role: LLMRole.system,
      content: '''You have access to tools. To use a tool, output JSON:
{"name": "tool_name", "arguments": {...}}''',
    ),
    ...
  ],
  tools: [MyTool()],
);
```

## Platform Support

| Platform | Architecture | GPU Support |
|----------|--------------|-------------|
| Linux    | x86_64       | CUDA, Vulkan |
| macOS    | arm64, x86_64 | Metal |
| Windows  | x86_64       | CUDA, Vulkan |
| Android  | arm64-v8a    | OpenCL (Adreno) |
| Android  | x86_64       | - |
| iOS      | arm64        | Metal |

## Configuration

```dart
LlamaCppChatRepository(
  contextSize: 4096,    // Token context window
  batchSize: 512,       // Batch size for processing
  threads: null,        // null = auto-detect
  nGpuLayers: 0,        // Layers to offload to GPU (99 = all)
  maxToolAttempts: 25,  // Max tool calling iterations
);
```

## Troubleshooting

### Library not found

Ensure the native library is accessible:
- Current directory
- System library path (`/usr/local/lib`, etc.)
- Next to your executable
- Set `LD_LIBRARY_PATH` (Linux) or `DYLD_LIBRARY_PATH` (macOS)

### Model loading errors

**"key not found in model"** - The GGUF is missing required metadata. Download from a different source (see Model Compatibility above).

**"Failed to load model"** - Check file path, permissions, and that it's a valid GGUF file.

### Out of memory

- Use a smaller model (Q4_K_M or Q4_0 quantization)
- Reduce context size
- Offload layers to GPU with `nGpuLayers`

### Slow inference

- Enable GPU acceleration (`nGpuLayers: 99`)
- Use a more aggressively quantized model (Q4_0 vs Q8_0)
- Reduce context size
- Increase batch size

### CUDA errors

- Ensure CUDA toolkit version matches your driver
- Check `nvidia-smi` for driver CUDA version
- Set `LD_LIBRARY_PATH` to include CUDA libs
