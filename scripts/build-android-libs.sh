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

# Check that llama.cpp submodule exists and is initialized
if [ ! -d "$LLAMACPP_DIR" ]; then
    echo "Error: llama.cpp directory not found at $LLAMACPP_DIR"
    echo "Please clone the submodule first:"
    echo "  cd packages/llm_llamacpp"
    echo "  git submodule add https://github.com/ggml-org/llama.cpp.git llamacpp"
    exit 1
fi

if [ ! -f "$LLAMACPP_DIR/CMakeLists.txt" ]; then
    echo "Error: llama.cpp submodule exists but is not initialized (CMakeLists.txt not found)"
    echo "Please initialize the submodule:"
    echo "  cd $PROJECT_ROOT"
    echo "  git submodule update --init --recursive"
    echo ""
    echo "Or if the submodule path is incorrect:"
    echo "  cd packages/llm_llamacpp"
    echo "  git submodule add https://github.com/ggml-org/llama.cpp.git llamacpp"
    exit 1
fi

# Preferred NDK version (should match build.gradle)
PREFERRED_NDK_VERSION="26.3.11579264"

# Find Android NDK
if [ -n "$ANDROID_NDK_HOME" ]; then
    NDK_PATH="$ANDROID_NDK_HOME"
elif [ -n "$ANDROID_NDK" ]; then
    NDK_PATH="$ANDROID_NDK"
else
    # Try to find preferred version first
    NDK_FOUND=false
    
    # Check common NDK locations for preferred version
    for ndk_base in \
        "$HOME/Library/Android/sdk/ndk" \
        "$HOME/Android/Sdk/ndk" \
        "/usr/local/android-sdk/ndk" \
        "/opt/android-sdk/ndk"
    do
        if [ -d "$ndk_base/$PREFERRED_NDK_VERSION" ]; then
            NDK_PATH="$ndk_base/$PREFERRED_NDK_VERSION"
            NDK_FOUND=true
            break
        fi
    done
    
    # If preferred version not found, use latest available
    if [ "$NDK_FOUND" = false ]; then
        for ndk_base in \
            "$HOME/Library/Android/sdk/ndk" \
            "$HOME/Android/Sdk/ndk" \
            "/usr/local/android-sdk/ndk" \
            "/opt/android-sdk/ndk"
        do
            if [ -d "$ndk_base" ]; then
                NDK_PATH=$(find "$ndk_base" -maxdepth 1 -type d | sort -V | tail -1)
                NDK_FOUND=true
                break
            fi
        done
    fi
    
    if [ "$NDK_FOUND" = false ]; then
        echo "Error: Android NDK not found. Please set ANDROID_NDK_HOME environment variable."
        echo ""
        echo "Expected NDK version: $PREFERRED_NDK_VERSION"
        echo "Please install it via Android Studio SDK Manager or set ANDROID_NDK_HOME"
        exit 1
    fi
fi

# Extract NDK version from path
NDK_VERSION=$(basename "$NDK_PATH")

# Warn if using different NDK version than preferred
if [ "$NDK_VERSION" != "$PREFERRED_NDK_VERSION" ]; then
    echo ""
    echo "=========================================="
    echo "WARNING: NDK version mismatch!"
    echo "=========================================="
    echo "Using NDK: $NDK_VERSION"
    echo "Preferred: $PREFERRED_NDK_VERSION (as specified in build.gradle)"
    echo ""
    echo "This may cause C++ standard library symbol mismatches at runtime."
    echo "To fix, install the preferred NDK version:"
    echo "  Android Studio > SDK Manager > SDK Tools > NDK (Side by side) > $PREFERRED_NDK_VERSION"
    echo ""
    echo "Or set ANDROID_NDK_HOME to point to the preferred version:"
    echo "  export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/$PREFERRED_NDK_VERSION"
    echo ""
    echo "Continuing with current NDK version..."
    echo ""
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
    echo "Configuring CMake (suppressing non-critical messages)..."
    
    # Filter CMake output to show only important messages and errors
    # Hide: deprecation warnings, feature detection tests, informational messages
    # Keep: errors, warnings (non-deprecation), configuration results
    {
        cmake "$LLAMACPP_DIR" "${CMAKE_ARGS[@]}" 2>&1 | \
        awk '
            # Always show errors and important warnings
            /[Ee][Rr][Rr][Oo][Rr]/ || /[Ff][Aa][Ii][Ll][Ee][Dd]/ || /[Ff][Aa][Tt][Aa][Ll]/ { print; next }
            # Show warnings except deprecation warnings
            /[Ww][Aa][Rr][Nn][Ii][Nn][Gg]/ && !/CMake Deprecation Warning/ { print; next }
            # Hide specific noisy patterns
            /CMake Deprecation Warning/ { next }
            /^-- Performing Test/ { next }
            /^-- Looking for/ { next }
            /^-- Check if compiler accepts/ { next }
            /^-- Detecting C/ { next }
            /^-- Detecting CXX/ { next }
            /^-- The C compiler/ { next }
            /^-- The CXX compiler/ { next }
            /^-- The ASM compiler/ { next }
            /^-- Found assembler:/ { next }
            /^-- Found Git:/ { next }
            /^CMAKE_BUILD_TYPE=/ { next }
            /^-- Setting GGML/ { next }
            /^-- ARM detected/ { next }
            /^-- Checking for ARM features/ { next }
            /^-- Using KleidiAI/ { next }
            /^-- Adding CPU backend variant/ { next }
            /^-- ggml version:/ { next }
            /^-- ggml commit:/ { next }
            /^-- Could NOT find OpenSSL/ { next }
            /^-- OpenSSL not found/ { next }
            /^-- Generating embedded license/ { next }
            /^-- Found OpenMP/ { next }
            /^-- Found Threads:/ { next }
            /^-- Warning: ccache/ { next }
            /^-- CMAKE_SYSTEM_PROCESSOR:/ { next }
            /^-- GGML_SYSTEM_ARCH:/ { next }
            /^-- Including CPU backend/ { next }
            /^2$/ { next }
            # Show everything else (including final status messages)
            { print }
        '
    }
    CMAKE_EXIT_CODE=${PIPESTATUS[0]}
    
    if [ $CMAKE_EXIT_CODE -ne 0 ]; then
        echo ""
        echo "ERROR: CMake configuration failed with exit code $CMAKE_EXIT_CODE"
        exit $CMAKE_EXIT_CODE
    fi
    
    echo "-- Configuring done"
    echo "-- Generating done"

    # Build core targets
    # Note: With GGML_CPU_ALL_VARIANTS=ON, ggml-cpu is replaced by multiple variant targets
    # Just build "all" and let CMake handle the dependencies
    echo ""
    echo "Building all targets..."
    
    # Get number of CPU cores (works on both Linux and macOS)
    if command -v nproc >/dev/null 2>&1; then
        NUM_CORES=$(nproc)
    elif command -v sysctl >/dev/null 2>&1; then
        NUM_CORES=$(sysctl -n hw.ncpu)
    else
        NUM_CORES=4  # Fallback to 4 cores
    fi
    
    # Build with filtered output - only show errors and important messages
    {
        cmake --build . --config Release -j${NUM_CORES} 2>&1 | \
        awk '
            # Always show errors
            /[Ee][Rr][Rr][Oo][Rr]/ || /[Ff][Aa][Ii][Ll][Ee][Dd]/ || /[Ff][Aa][Tt][Aa][Ll]/ { print; next }
            # Show warnings
            /[Ww][Aa][Rr][Nn][Ii][Nn][Gg]/ { print; next }
            # Hide build progress messages
            /^\[/ { next }
            /Scanning dependencies/ { next }
            /Building CXX object/ { next }
            /Building C object/ { next }
            /Linking CXX shared library/ { next }
            /Linking C shared library/ { next }
            /^-- / { next }
            # Show everything else
            { print }
        '
    }
    BUILD_EXIT_CODE=${PIPESTATUS[0]}
    
    if [ $BUILD_EXIT_CODE -ne 0 ]; then
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

    # Required libraries that must be present
    local REQUIRED_LIBS=("libllama.so" "libggml.so" "libggml-base.so")
    local found_libs=()

    # Copy libllama.so
    local found_llama=false
    for src_dir in "${SRC_DIRS[@]}"; do
        if [ -f "$src_dir/libllama.so" ]; then
            cp "$src_dir/libllama.so" "$JNILIBS_DIR/$ABI/"
            echo "  ✓ Copied libllama.so"
            found_llama=true
            found_libs+=("libllama.so")
            break
        fi
    done
    if [ "$found_llama" = false ]; then
        echo "  ✗ ERROR: libllama.so not found!"
    fi

    # Copy core ggml libraries
    local GGML_DIRS=(
        "$BUILD_DIR/$ABI/bin"
        "$BUILD_DIR/$ABI/ggml/src"
        "$BUILD_DIR/$ABI"
    )

    # Copy core ggml libraries
    for lib in libggml.so libggml-base.so; do
        local found=false
        for src_dir in "${GGML_DIRS[@]}"; do
            if [ -f "$src_dir/$lib" ] && [ ! -f "$JNILIBS_DIR/$ABI/$lib" ]; then
                cp "$src_dir/$lib" "$JNILIBS_DIR/$ABI/"
                echo "  ✓ Copied $lib"
                found=true
                found_libs+=("$lib")
                break
            elif [ -f "$JNILIBS_DIR/$ABI/$lib" ]; then
                # Already copied from a previous directory
                found=true
                found_libs+=("$lib")
                break
            fi
        done
        if [ "$found" = false ]; then
            echo "  ✗ ERROR: $lib not found!"
        fi
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
    
    # Copy libomp.so from NDK (required for OpenMP support in CPU backends)
    # This is needed because the CPU backends are built with GGML_OPENMP=ON
    if [ "$ABI" = "arm64-v8a" ]; then
        local OMP_ARCH="aarch64"
    elif [ "$ABI" = "x86_64" ]; then
        local OMP_ARCH="x86_64"
    else
        local OMP_ARCH=""
    fi
    
    if [ -n "$OMP_ARCH" ]; then
        # Find libomp.so in NDK
        local OMP_LIB=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -path "*lib/linux/$OMP_ARCH/libomp.so" -type f 2>/dev/null | head -1)
        if [ -n "$OMP_LIB" ] && [ -f "$OMP_LIB" ]; then
            cp "$OMP_LIB" "$JNILIBS_DIR/$ABI/"
            echo "  ✓ Copied libomp.so (OpenMP runtime)"
        else
            echo "  ⚠ Warning: libomp.so not found in NDK for $OMP_ARCH"
            echo "    CPU backends may fail to load at runtime."
            echo "    NDK path: $NDK_PATH"
        fi
    fi

    # Validate that all required libraries were copied
    echo ""
    echo "Validating required libraries for $ABI..."
    local missing_libs=()
    for lib in "${REQUIRED_LIBS[@]}"; do
        if [ ! -f "$JNILIBS_DIR/$ABI/$lib" ]; then
            missing_libs+=("$lib")
        fi
    done

    if [ ${#missing_libs[@]} -gt 0 ]; then
        echo ""
        echo "=========================================="
        echo "ERROR: Missing required libraries for $ABI!"
        echo "=========================================="
        echo "Missing libraries:"
        for lib in "${missing_libs[@]}"; do
            echo "  - $lib"
        done
        echo ""
        echo "Location: $JNILIBS_DIR/$ABI/"
        echo "Please check the build output above for errors."
        return 1
    fi

    echo "  ✓ All required libraries present"
    
    # Optional: Verify library dependencies using readelf
    # This checks that libllama.so actually declares dependencies on libggml.so
    if command -v readelf >/dev/null 2>&1; then
        local llama_so="$JNILIBS_DIR/$ABI/libllama.so"
        if [ -f "$llama_so" ]; then
            echo ""
            echo "Verifying library dependencies using readelf..."
            local deps=$(readelf -d "$llama_so" 2>/dev/null | grep "NEEDED" | sed 's/.*\[\(.*\)\]/\1/' || true)
            local has_ggml=false
            local has_ggml_base=false
            
            while IFS= read -r dep; do
                if [[ "$dep" == *"libggml.so"* ]]; then
                    has_ggml=true
                fi
                if [[ "$dep" == *"libggml-base.so"* ]]; then
                    has_ggml_base=true
                fi
            done <<< "$deps"
            
            if [ "$has_ggml" = true ] || [ "$has_ggml_base" = true ]; then
                echo "  ✓ Verified libllama.so dependencies"
                if [ "$has_ggml" = true ]; then
                    echo "    - Depends on libggml.so"
                fi
                if [ "$has_ggml_base" = true ]; then
                    echo "    - Depends on libggml-base.so"
                fi
            else
                echo "  ⚠ Warning: Could not verify dependencies (readelf may not show all dependencies)"
            fi
        fi
    fi
    
    return 0
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
        if ! copy_libraries "x86_64"; then
            echo "ERROR: Failed to copy libraries for x86_64"
            exit 1
        fi
    else
        echo "WARNING: x86_64 build failed, continuing with arm64..."
    fi
fi

# Build for arm64-v8a (physical devices)
if [ "$BUILD_ARM64" = "ON" ]; then
    if ! build_for_abi "arm64-v8a" "android-28"; then
        echo "ERROR: Build failed for arm64-v8a"
        exit 1
    fi
    if ! copy_libraries "arm64-v8a"; then
        echo "ERROR: Failed to copy libraries for arm64-v8a"
        exit 1
    fi
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

# Final validation: Check for critical missing libraries
# This is a redundant check in case copy_libraries() didn't catch everything
validation_failed=false
for ABI in arm64-v8a x86_64; do
    if [ -d "$JNILIBS_DIR/$ABI" ]; then
        missing=()
        for lib in libllama.so libggml.so libggml-base.so; do
            if [ ! -f "$JNILIBS_DIR/$ABI/$lib" ]; then
                missing+=("$lib")
            fi
        done
        
        if [ ${#missing[@]} -gt 0 ]; then
            echo ""
            echo "=========================================="
            echo "ERROR: Essential libraries are missing for $ABI!"
            echo "=========================================="
            echo "Missing libraries:"
            for lib in "${missing[@]}"; do
                echo "  - $lib"
            done
            echo ""
            echo "Location: $JNILIBS_DIR/$ABI/"
            echo "The build may have failed. Check the build output above for errors."
            validation_failed=true
        fi
    fi
done

if [ "$validation_failed" = true ]; then
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
