import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llm_llamacpp/src/backend_initializer.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/generation_options.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';

part 'native_template_applier.dart';
part 'inference_isolate_handler.dart';
part 'inference_isolate_messages.dart';
part 'inference_sampler_config.dart';
part 'inference_token_generator.dart';

/// Manages a persistent inference isolate for running LLM inference.
///
/// This follows the pattern used by fllama: a single persistent isolate
/// handles all inference requests, avoiding the issues caused by
/// re-initializing the library in multiple isolates.
///
/// The isolate is lazily initialized on first use and stays alive for the
/// lifetime of the application. This is important because:
/// 1. Native library state (backends) is shared across the process
/// 2. Re-loading libraries in separate isolates causes FFI issues on Android
/// 3. A persistent isolate avoids the overhead of spawning new isolates
class PersistentInferenceIsolate {
  PersistentInferenceIsolate._();

  static final PersistentInferenceIsolate _instance =
      PersistentInferenceIsolate._();
  static PersistentInferenceIsolate get instance => _instance;

  SendPort? _helperSendPort;
  Isolate? _helperIsolate;
  ReceivePort? _mainReceivePort;
  bool _initializing = false;

  /// Mapping from request IDs to response controllers
  final Map<int, StreamController<dynamic>> _pendingRequests = {};
  int _nextRequestId = 0;

  /// Initialize the persistent isolate if not already running.
  Future<void> _ensureInitialized() async {
    if (_helperSendPort != null) return;
    if (_initializing) {
      // Wait for initialization to complete
      while (_helperSendPort == null) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return;
    }

    _initializing = true;
    try {
      final completer = Completer<SendPort>();
      _mainReceivePort = ReceivePort();

      _mainReceivePort!.listen((message) {
        if (message is SendPort) {
          completer.complete(message);
          return;
        }

        // Handle responses from the helper isolate
        if (message is _IsolateResponse) {
          final controller = _pendingRequests[message.requestId];
          if (controller != null) {
            controller.add(message.payload);
            if (message.isComplete) {
              controller.close();
              _pendingRequests.remove(message.requestId);
            }
          }
        }
      });

      // ignore: avoid_print
      print('[PersistentInferenceIsolate] Spawning helper isolate...');
      _helperIsolate = await Isolate.spawn(
        _isolateMain,
        _mainReceivePort!.sendPort,
      );

      _helperSendPort = await completer.future;
      // ignore: avoid_print
      print('[PersistentInferenceIsolate] Helper isolate ready');
    } finally {
      _initializing = false;
    }
  }

  /// Run inference and return a stream of responses.
  ///
  /// If [messages] is provided, uses the model's built-in chat template via
  /// llama_chat_apply_template(). Otherwise, uses the pre-formatted [prompt].
  Stream<dynamic> runInference({
    required String modelPath,
    required String prompt,
    required List<String> stopTokens,
    required int contextSize,
    required int batchSize,
    required int nGpuLayers,
    required GenerationOptions options,
    int? threads,
    String? loraPath,
    double loraScale = 1.0,
    List<IsolateMessage>? messages,
  }) async* {
    await _ensureInitialized();

    final requestId = _nextRequestId++;
    final controller = StreamController<dynamic>();
    _pendingRequests[requestId] = controller;

    // Send the request to the helper isolate
    _helperSendPort!.send(
      _InferenceRequestMessage(
        requestId: requestId,
        modelPath: modelPath,
        prompt: prompt,
        stopTokens: stopTokens,
        contextSize: contextSize,
        batchSize: batchSize,
        nGpuLayers: nGpuLayers,
        options: options,
        threads: threads,
        loraPath: loraPath,
        loraScale: loraScale,
        messages: messages,
      ),
    );

    try {
      yield* controller.stream;
    } finally {
      // Ensure controller is closed if stream is cancelled or errors
      if (_pendingRequests.containsKey(requestId)) {
        // ignore: unawaited_futures
        controller.close();
        _pendingRequests.remove(requestId);
      }
    }
  }

  /// Shutdown the persistent isolate.
  void dispose() {
    _helperIsolate?.kill();
    _helperIsolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _helperSendPort = null;
    for (final controller in _pendingRequests.values) {
      // ignore: unawaited_futures
      controller.close();
    }
    _pendingRequests.clear();
  }
}

/// The main entry point for the helper isolate.
void _isolateMain(SendPort mainSendPort) {
  // ignore: avoid_print
  print('[InferenceHelperIsolate] Starting...');

  // Initialize the library in this isolate
  // Since the main isolate no longer calls any llama.cpp functions (using withModelPath),
  // we need to do FULL initialization here including loading all backends.
  late final ffi.DynamicLibrary lib;
  late final LlamaBindings bindings;

  try {
    // ignore: avoid_print
    print(
      '[InferenceHelperIsolate] Initializing backend (full initialization)...',
    );
    // Use full initialization since main isolate does NO FFI calls
    final result = BackendInitializer.initializeBackend();
    lib = result.$1;
    bindings = result.$2;
    // ignore: avoid_print
    print('[InferenceHelperIsolate] Backend initialized successfully');
  } catch (e) {
    // ignore: avoid_print
    print('[InferenceHelperIsolate] ERROR initializing backend: $e');
    return;
  }

  // Create receive port for requests from main isolate
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is _InferenceRequestMessage) {
      _handleInferenceRequest(message, mainSendPort, lib, bindings);
    }
  });

  // ignore: avoid_print
  print('[InferenceHelperIsolate] Ready to accept requests');
}
