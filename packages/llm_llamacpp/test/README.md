# llm_llamacpp Integration Tests

Comprehensive test suite for the llm_llamacpp package covering model loading, text generation, vision models, and tool use.

## Quick Start

```bash
cd packages/llm_llamacpp

# Run all tests (with models in /tmp/)
LD_LIBRARY_PATH=linux/libs dart test test/all_tests.dart

# Run specific test file
LD_LIBRARY_PATH=linux/libs dart test test/model_loading_test.dart
```

## Test Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `LLAMA_TEST_MODEL` | Path to text model | `/path/to/qwen2.5-0.5b-q4.gguf` |
| `LLAMA_TEST_VISION_MODEL` | Path to vision model | `/path/to/qwen3-vl-8b-q4.gguf` |
| `LLAMA_TEST_SMALL_MODEL` | Path to small/fast model | `/path/to/tiny-model.gguf` |
| `LLAMA_TEST_GPU_LAYERS` | GPU layers to offload | `99` (all) or `0` (none) |

### Local Model Directory

Alternatively, place models in `test/models/`:
- `test/models/text.gguf` - Standard text model
- `test/models/vision.gguf` - Vision model
- `test/models/small.gguf` - Small/fast model

### Example with Full Configuration

```bash
LLAMA_TEST_MODEL=/tmp/qwen2.5-0.5b-q4.gguf \
LLAMA_TEST_VISION_MODEL=/tmp/qwen3-vl-8b-q4km.gguf \
LLAMA_TEST_GPU_LAYERS=99 \
LD_LIBRARY_PATH=linux/libs:/usr/local/cuda/lib64 \
dart test test/all_tests.dart
```

## Test Files

### `model_loading_test.dart`
- Model loading and unloading
- GPU offloading
- Memory mapping options
- Error handling for invalid models
- Model metadata access

### `text_generation_test.dart`
- Basic text generation
- Streaming token output
- System prompts
- Multi-turn conversations
- Prompt templates (ChatML, Llama3, etc.)
- Performance metrics

### `vision_model_test.dart`
- Vision model loading
- Text-only inference with vision models
- Conversation maintenance
- Special token handling
- Compatibility documentation

### `tool_use_test.dart`
- Tool definition and execution
- JSON tool call parsing
- XML-wrapped tool calls
- Multiple tools
- Tool execution limits
- Extra context passing

## Downloading Test Models

### Small Text Model (Qwen2.5-0.5B)
```bash
wget -O /tmp/qwen2.5-0.5b-q4.gguf \
  "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
```

### Vision Model (Qwen3-VL-8B)
```bash
wget -O /tmp/qwen3-vl-8b-q4km.gguf \
  "https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/resolve/main/Qwen3-VL-8B-Instruct-Q4_K_M.gguf"
```

### Larger Text Model (Llama-3.2-1B)
```bash
wget -O /tmp/llama-3.2-1b-q4.gguf \
  "https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
```

## Running with GPU Acceleration

### NVIDIA (CUDA)
```bash
# Ensure CUDA is in path
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=linux/libs:/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Run with GPU
LLAMA_TEST_GPU_LAYERS=99 dart test test/all_tests.dart
```

### Apple Silicon (Metal)
```bash
# Metal is auto-detected, just ensure library is built with Metal support
dart test test/all_tests.dart
```

## Test Output

Tests print detailed information about:
- Model loading times
- Vocabulary and context sizes
- Generated responses
- Token counts and generation speed
- Tool execution results

Example output:
```
╔════════════════════════════════════════════════════════════╗
║              llm_llamacpp Integration Tests                 ║
╠════════════════════════════════════════════════════════════╣
║ Text Model:   ✅ qwen2.5-0.5b-q4.gguf (463MB)              ║
║ Vision Model: ✅ qwen3-vl-8b-q4km.gguf (4.7GB)             ║
║ Small Model:  ✅ qwen2.5-0.5b-q4.gguf (463MB)              ║
║ GPU Layers:   99                                            ║
╚════════════════════════════════════════════════════════════╝

Loading model: /tmp/qwen2.5-0.5b-q4.gguf
Loaded in 715ms
  Vocab size: 151936
  Context size (train): 32768
  Embedding size: 896
```

## Skipped Tests

Tests are automatically skipped when:
- Required model is not available
- Model path doesn't exist
- GPU not available (for GPU-specific tests)

Skipped tests print informative messages about how to enable them.

## Troubleshooting

### "Library not found"
```bash
# Ensure LD_LIBRARY_PATH includes the libs directory
export LD_LIBRARY_PATH=linux/libs:$LD_LIBRARY_PATH
```

### "No model available"
```bash
# Set the model path
export LLAMA_TEST_MODEL=/path/to/your/model.gguf
```

### Tests timeout
```bash
# Increase timeout for slow machines
dart test test/all_tests.dart --timeout 5m
```

### CUDA errors
```bash
# Ensure CUDA libraries are accessible
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Or run CPU-only
export LLAMA_TEST_GPU_LAYERS=0
```

