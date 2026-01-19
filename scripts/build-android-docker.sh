#!/bin/bash
# Build llama.cpp Android libraries using Docker
# This provides a consistent Linux build environment for cross-compilation
#
# Usage:
#   ./scripts/build-android-docker.sh                    # Build arm64 with CPU acceleration
#   BUILD_X86_64=ON ./scripts/build-android-docker.sh    # Also build for emulator

set -e

echo "=========================================="
echo "Building Android libraries with Docker"
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Build Docker image
echo ""
echo "Building Docker image..."
docker build -t llamacpp-android-builder -f "$SCRIPT_DIR/Dockerfile.android-build" "$PROJECT_ROOT"

echo ""
echo "Running build inside Docker container..."

# Clean previous build artifacts
rm -rf "$PROJECT_ROOT/build-android"

# Run the Docker container
# --platform linux/amd64 is required for Apple Silicon Macs to run x86_64 NDK tools
docker run --rm \
    --platform linux/amd64 \
    -v "$PROJECT_ROOT:/workspace" \
    -e BUILD_X86_64=${BUILD_X86_64:-OFF} \
    -e BUILD_ARM64=${BUILD_ARM64:-ON} \
    llamacpp-android-builder

echo ""
echo "=========================================="
echo "Docker build complete!"
echo "=========================================="
echo ""
echo "Libraries are in: packages/llm_llamacpp/android/src/main/jniLibs/"
echo ""
echo "Next steps:"
echo "  cd packages/llm_llamacpp/example_app"
echo "  flutter clean && flutter run"
