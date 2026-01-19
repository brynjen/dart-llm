#include <flutter_linux/flutter_linux.h>

// This FFI plugin doesn't need method channel registration,
// but we need this file for the CMake build to work.

extern "C" {
void llm_llamacpp_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  // No-op for FFI plugin
}
}

