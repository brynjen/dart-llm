#!/bin/bash
# Build llama.cpp native libraries for Android from local submodule
# Uses CPU hardware acceleration (KleidiAI, SME2/SVE2, AMX) following official llama.cpp approach
#
# Requirements:
#   - Android NDK installed (26.x or newer)
#   - Ninja build system
#
# Usage:
#   ./build-android-libs.sh                    # Build with CPU acceleration
#   BUILD_X86_64=ON ./build-android-libs.sh    # Also build for emulator
#
# Environment Variables:
#   BUILD_X86_64  - ON/OFF (default: OFF) - Build for x86_64 (emulator)
#   BUILD_ARM64   - ON/OFF (default: ON)  - Build for arm64-v8a (real devices)
#
# CPU Hardware Acceleration Features:
#   - KleidiAI: Arm's optimized inference library (arm64)
#   - SME2/SVE2: Scalable Matrix/Vector Extensions (arm64)
#   - AMX: Advanced Matrix Extensions (x86_64)
#   - Dynamic backend loading for runtime feature detection

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LLAMACPP_DIR="$PROJECT_ROOT/packages/llm_llamacpp/llamacpp"
BUILD_DIR="$PROJECT_ROOT/build-android"

# Build options (can be overridden via environment variables)
BUILD_X86_64=${BUILD_X86_64:-OFF}
BUILD_ARM64=${BUILD_ARM64:-ON}

# Check that llama.cpp submodule exists
if [ ! -d "$LLAMACPP_DIR" ]; then
    echo "Error: llama.cpp not found at $LLAMACPP_DIR"
    echo "Please clone the submodule first:"
    echo "  cd packages/llm_llamacpp"
    echo "  git submodule add https://github.com/ggml-org/llama.cpp.git llamacpp"
    exit 1
fi

# Find Android NDK
if [ -n "$ANDROID_NDK_HOME" ]; then
    NDK_PATH="$ANDROID_NDK_HOME"
elif [ -n "$ANDROID_NDK" ]; then
    NDK_PATH="$ANDROID_NDK"
elif [ -d "$HOME/Android/Sdk/ndk" ]; then
    NDK_PATH=$(find "$HOME/Android/Sdk/ndk" -maxdepth 1 -type d | sort -V | tail -1)
elif [ -d "/usr/local/android-sdk/ndk" ]; then
    NDK_PATH=$(find "/usr/local/android-sdk/ndk" -maxdepth 1 -type d | sort -V | tail -1)
elif [ -d "/opt/android-sdk/ndk" ]; then
    # Docker container path
    NDK_PATH=$(find "/opt/android-sdk/ndk" -maxdepth 1 -type d | sort -V | tail -1)
elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
    # macOS Android Studio path
    NDK_PATH=$(find "$HOME/Library/Android/sdk/ndk" -maxdepth 1 -type d | sort -V | tail -1)
else
    echo "Error: Android NDK not found. Please set ANDROID_NDK_HOME environment variable."
    exit 1
fi

echo "Using Android NDK: $NDK_PATH"
TOOLCHAIN="$NDK_PATH/build/cmake/android.toolchain.cmake"

if [ ! -f "$TOOLCHAIN" ]; then
    echo "Error: NDK toolchain not found at $TOOLCHAIN"
    exit 1
fi

echo "Using llama.cpp from: $LLAMACPP_DIR"

# Create build directory
mkdir -p "$BUILD_DIR"

# ==========================================
# Build function for a specific ABI
# ==========================================
build_for_abi() {
    local ABI=$1
    local PLATFORM=$2

    echo ""
    echo "=========================================="
    echo "Building for $ABI with CPU acceleration..."
    echo "=========================================="

    rm -rf "$BUILD_DIR/$ABI"
    mkdir -p "$BUILD_DIR/$ABI"
    cd "$BUILD_DIR/$ABI"

    # Base CMake arguments - following official llama.cpp Android example
    local CMAKE_ARGS=(
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
        -DANDROID_ABI="$ABI"
        -DANDROID_PLATFORM="$PLATFORM"
        -DCMAKE_BUILD_TYPE=Release
        
        # Disable features not needed for library
        -DLLAMA_BUILD_TESTS=OFF
        -DLLAMA_BUILD_EXAMPLES=OFF
        -DLLAMA_BUILD_SERVER=OFF
        -DLLAMA_BUILD_TOOLS=OFF
        -DLLAMA_CURL=OFF
        
        # Build as shared libraries
        -DBUILD_SHARED_LIBS=ON
        
        # Disable features that don't work on Android
        -DGGML_NATIVE=OFF
        -DGGML_LLAMAFILE=OFF
        
        # === CPU Hardware Acceleration (from official Android example) ===
        -DGGML_BACKEND_DL=ON          # Dynamic backend loading
        -DGGML_CPU_ALL_VARIANTS=ON    # All CPU optimizations (SME2, SVE2, AMX)
    )

    # ABI-specific optimizations
    if [ "$ABI" = "arm64-v8a" ]; then
        echo "  Enabling arm64 optimizations: KleidiAI, OpenMP"
        CMAKE_ARGS+=(
            -DGGML_CPU_KLEIDIAI=ON    # Arm's optimized inference library
            -DGGML_OPENMP=ON          # OpenMP for parallelization
        )
    else
        echo "  x86_64 build (emulator): Basic CPU backend"
        CMAKE_ARGS+=(
            -DGGML_CPU_KLEIDIAI=OFF
            -DGGML_OPENMP=OFF
        )
    fi

    # Configure
    echo ""
    echo "CMake configuration:"
    for arg in "${CMAKE_ARGS[@]}"; do
        echo "  $arg"
    done
    echo ""
    
    cmake "$LLAMACPP_DIR" "${CMAKE_ARGS[@]}"

    # Build core targets
    # Note: With GGML_CPU_ALL_VARIANTS=ON, ggml-cpu is replaced by multiple variant targets
    # Just build "all" and let CMake handle the dependencies
    echo ""
    echo "Building all targets..."
    if ! cmake --build . --config Release -j$(nproc); then
        echo ""
        echo "=========================================="
        echo "ERROR: Build failed for $ABI!"
        echo "=========================================="
        echo "Check the error messages above."
        return 1
    fi
    
    echo ""
    echo "Build completed for $ABI"
}

# ==========================================
# Copy libraries function
# ==========================================
copy_libraries() {
    local ABI=$1
    local JNILIBS_DIR="$PROJECT_ROOT/packages/llm_llamacpp/android/src/main/jniLibs"

    echo ""
    echo "Copying $ABI libraries to jniLibs..."

    # Clear existing libraries for this ABI
    rm -rf "$JNILIBS_DIR/$ABI"
    mkdir -p "$JNILIBS_DIR/$ABI"

    # Possible source directories
    local SRC_DIRS=(
        "$BUILD_DIR/$ABI/bin"
        "$BUILD_DIR/$ABI/src"
        "$BUILD_DIR/$ABI"
    )

    # Debug: show what was built
    echo "  Built libraries:"
    find "$BUILD_DIR/$ABI" -name "*.so" -type f 2>/dev/null | head -20

    # Copy libllama.so
    local found_llama=false
    for src_dir in "${SRC_DIRS[@]}"; do
        if [ -f "$src_dir/libllama.so" ]; then
            cp "$src_dir/libllama.so" "$JNILIBS_DIR/$ABI/"
            echo "  ✓ Copied libllama.so"
            found_llama=true
            break
        fi
    done
    if [ "$found_llama" = false ]; then
        echo "  ✗ WARNING: libllama.so not found!"
    fi

    # Copy core ggml libraries
    local GGML_DIRS=(
        "$BUILD_DIR/$ABI/bin"
        "$BUILD_DIR/$ABI/ggml/src"
        "$BUILD_DIR/$ABI"
    )

    # Copy core ggml libraries
    for src_dir in "${GGML_DIRS[@]}"; do
        for lib in libggml.so libggml-base.so; do
            if [ -f "$src_dir/$lib" ] && [ ! -f "$JNILIBS_DIR/$ABI/$lib" ]; then
                cp "$src_dir/$lib" "$JNILIBS_DIR/$ABI/"
                echo "  ✓ Copied $lib"
            fi
        done
    done

    # Copy CPU backend variants (dynamically loaded at runtime for feature detection)
    # With GGML_CPU_ALL_VARIANTS=ON, there are multiple variants like:
    # - libggml-cpu-android_armv8.0_1.so (baseline)
    # - libggml-cpu-android_armv8.2_1.so (dotprod)
    # - libggml-cpu-android_armv9.2_1.so (SME2)
    # etc.
    local cpu_count=0
    for lib in $(find "$BUILD_DIR/$ABI" -name "libggml-cpu*.so" -type f 2>/dev/null); do
        local libname=$(basename "$lib")
        if [ ! -f "$JNILIBS_DIR/$ABI/$libname" ]; then
            cp "$lib" "$JNILIBS_DIR/$ABI/"
            cpu_count=$((cpu_count + 1))
        fi
    done
    if [ $cpu_count -gt 0 ]; then
        echo "  ✓ Copied $cpu_count CPU backend variants"
    fi
}

# ==========================================
# Main Build Process
# ==========================================

echo ""
echo "=========================================="
echo "Android Build Configuration"
echo "=========================================="
echo "  CPU Acceleration: KleidiAI + SME2/SVE2 + AMX"
echo "  Dynamic Backend:  ON (runtime feature detection)"
echo "  Build x86_64:     $BUILD_X86_64"
echo "  Build arm64:      $BUILD_ARM64"
echo ""

# Build for x86_64 (emulator)
if [ "$BUILD_X86_64" = "ON" ]; then
    if build_for_abi "x86_64" "android-28"; then
        copy_libraries "x86_64"
    else
        echo "WARNING: x86_64 build failed, continuing with arm64..."
    fi
fi

# Build for arm64-v8a (physical devices)
if [ "$BUILD_ARM64" = "ON" ]; then
    build_for_abi "arm64-v8a" "android-28"
    copy_libraries "arm64-v8a"
fi

# ==========================================
# Summary
# ==========================================
JNILIBS_DIR="$PROJECT_ROOT/packages/llm_llamacpp/android/src/main/jniLibs"

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo ""
echo "Libraries in $JNILIBS_DIR:"
find "$JNILIBS_DIR" -name "*.so" -type f 2>/dev/null | sort | while read f; do
    size=$(du -h "$f" | cut -f1)
    arch=$(basename $(dirname "$f"))
    name=$(basename "$f")
    echo "  $arch/$name ($size)"
done

echo ""
echo "CPU Hardware Acceleration:"
echo "  ✓ KleidiAI (Arm optimized inference)"
echo "  ✓ SME2/SVE2 (Scalable Matrix/Vector Extensions)"
echo "  ✓ Dynamic backend loading (runtime detection)"

# Check for critical missing libraries
if [ ! -f "$JNILIBS_DIR/arm64-v8a/libllama.so" ] || [ ! -f "$JNILIBS_DIR/arm64-v8a/libggml.so" ]; then
    echo ""
    echo "=========================================="
    echo "WARNING: Essential libraries are missing!"
    echo "=========================================="
    echo "The build may have failed. Check the build output above for errors."
    exit 1
fi

# Check for CPU backend variants
CPU_VARIANTS=$(find "$JNILIBS_DIR/arm64-v8a" -name "libggml-cpu*.so" 2>/dev/null | wc -l)
if [ "$CPU_VARIANTS" -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "WARNING: No CPU backend variants found!"
    echo "=========================================="
    echo "CPU hardware acceleration may not work correctly."
fi

echo ""
echo "Now rebuild your Flutter app:"
echo "  cd $PROJECT_ROOT/packages/llm_llamacpp/example_app"
echo "  flutter clean && flutter run"
