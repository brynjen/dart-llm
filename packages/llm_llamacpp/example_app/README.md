# llm_llamacpp Example App

Flutter test app for llm_llamacpp on Android and iOS.

## Prerequisites

### 1. Native Libraries

Before running, you need the llama.cpp native libraries:

**Option A: Download from CI**
1. Go to [GitHub Actions](https://github.com/brynjen/dart-ollama/actions/workflows/build-llamacpp.yaml)
2. Run the "Build llama.cpp" workflow
3. Download the `llm-llamacpp-native-libs` artifact
4. Extract and copy libraries:
   ```bash
   # Android
   cp -r plugin/android/src/main/jniLibs/* ../android/src/main/jniLibs/
   
   # iOS
   cp -r plugin/ios/Frameworks/* ../ios/Frameworks/
   ```

**Option B: Build manually**
See the main [llm_llamacpp README](../README.md) for build instructions.

### 2. Verify Libraries

```bash
# Check Android libraries exist
ls -la ../android/src/main/jniLibs/arm64-v8a/
ls -la ../android/src/main/jniLibs/x86_64/

# Check iOS framework exists  
ls -la ../ios/Frameworks/llama.xcframework/
```

## Running the App

### Android Emulator (x86_64)

```bash
flutter run -d emulator-5554
```

### Android Device (arm64-v8a)

```bash
# List devices
flutter devices

# Run on device
flutter run -d <device-id>
```

### iOS Simulator

```bash
flutter run -d "iPhone 15 Pro"
```

## Features

1. **Model Download** - Downloads Qwen2.5-0.5B (~400MB) from HuggingFace
2. **Chat Interface** - Stream chat with the local model
3. **Offline Inference** - Works completely offline after model download

## Troubleshooting

### "Library not found" on Android

Make sure the `.so` files are in the correct jniLibs directories:
- `android/src/main/jniLibs/arm64-v8a/libllama.so` (device)
- `android/src/main/jniLibs/x86_64/libllama.so` (emulator)

### "Symbol not found" on iOS

Ensure the xcframework is properly placed:
- `ios/Frameworks/llama.xcframework/`

### Model download fails

- Check internet connection
- Verify the HuggingFace model exists
- Check app has storage permissions

### Slow inference

- This is expected on mobile devices
- The 0.5B model should generate ~10-20 tokens/second on modern phones
- Larger models will be significantly slower
