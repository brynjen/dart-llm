# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-19

### Added

- Initial release
- Local on-device inference with GGUF models via llama.cpp
- Cross-platform support: Android, iOS, macOS, Windows, Linux
- Streaming token generation with isolate-based inference
- Multiple prompt templates: ChatML, Llama2, Llama3, Alpaca, Vicuna, Phi-3
- Tool calling support via prompt convention
- GPU acceleration support (CUDA, Metal, Vulkan)
- Model management features:
  - Model discovery in directories
  - Model loading with pooling (reference counting)
  - GGUF metadata reading without loading
  - HuggingFace model downloading
  - Safetensors to GGUF conversion
- Native Assets build hook for automatic binary management
- Prebuilt binaries available via GitHub Releases
