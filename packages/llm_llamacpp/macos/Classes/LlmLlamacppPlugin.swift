import FlutterMacOS
import Foundation

// This plugin class exists solely to satisfy CocoaPods' requirement for a
// source_files entry. The actual native library (libllama.dylib) is provided
// at build time via the Native Assets hook (hook/build.dart), which downloads
// or builds it from the llama.cpp submodule.
public class LlmLlamacppPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // No registration needed — all FFI calls go through dart:ffi directly.
  }
}
