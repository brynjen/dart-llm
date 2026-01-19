#include <flutter/plugin_registrar_windows.h>

// This FFI plugin doesn't need method channel registration,
// but we need this file for the CMake build to work.

void LlmLlamacppPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  // No-op for FFI plugin
}

