# llm_llamacpp Example App

Flutter test app for llm_llamacpp on Android and iOS.

## Prerequisites

Just Flutter. The native libraries are handled by `llm_llamacpp`'s native-assets
build hook — there is nothing to download and nothing to copy. `flutter run`
triggers the hook, which fetches a prebuilt bundle (or builds from the vendored
submodule) and bundles the libraries into the app.

Nothing should be placed in `android/src/main/jniLibs/` by hand: the plugin's
`android/build.gradle` sets `jniLibs.srcDirs = []` precisely so hook output is
the only source, and anything copied there is ignored.

See the main [llm_llamacpp README](../README.md#native-library) for how
resolution works and which environment variables can override it.

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

1. **Model Download** — Downloads LiquidAI LFM2.5-1.2B-Instruct Q4_K_M (~731 MB).
2. **Text Chat** — Streaming chat with the local LFM2.5 text model.
3. **Tool Calling** — A calculator tool, toggleable in the UI. Each call renders
   as a subdued thinking bubble showing the invocation and its result. The app
   replays `LLMChunkMessage.rawContent` into history, which is what keeps tool
   calling working past the first turn.
4. **Offline Inference** — Works completely offline after the model is downloaded.

## Troubleshooting

### "Library not found" / "Symbol not found"

The build hook failed to produce or bundle the native libraries. Check the
`flutter run` output for the hook's messages — it logs the ABI fingerprint, the
prebuilt URL it tried, and whether it fell back to a source build. Copying
libraries by hand will not help; the plugin ignores hand-placed `jniLibs`.

### Model download fails

- Check internet connection
- Verify the HuggingFace model exists
- Check app has storage permissions

### "no backends are loaded" on Android

This error occurs when native libraries are loaded directly from the APK instead of being extracted to the filesystem. To fix:

Add `android:extractNativeLibs="true"` to your `AndroidManifest.xml`:

```xml
<application
    android:extractNativeLibs="true"
    ...>
```

This is required because `ggml_backend_load_all_from_path()` needs a real filesystem directory to find backend `.so` files.

### Slow inference

- This is expected on mobile devices
- Expect single-digit to low-double-digit tokens/second for the bundled
  LFM2.5-1.2B on a modern phone
- Larger models will be significantly slower
