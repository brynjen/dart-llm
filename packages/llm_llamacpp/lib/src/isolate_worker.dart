import 'dart:async';
import 'dart:isolate';

import 'package:llm_llamacpp/src/generation_options.dart';

/// Base class for isolate worker messages.
// ignore: unused_element
abstract class _WorkerMessage {}

/// Request to initialize a model in the worker.
// ignore: unused_element
class _InitModelMessage extends _WorkerMessage {
  _InitModelMessage({
    required this.modelPath,
    required this.nGpuLayers,
    required this.sendPort,
  });

  final String modelPath;
  final int nGpuLayers;
  final SendPort sendPort;
}

/// Request to run inference.
// ignore: unused_element
class _InferenceRequestMessage extends _WorkerMessage {
  _InferenceRequestMessage({
    required this.requestId,
    required this.prompt,
    required this.stopTokens,
    required this.contextSize,
    required this.batchSize,
    required this.threads,
    required this.options,
    required this.loraPath,
    required this.loraScale,
  });

  final int requestId;
  final String prompt;
  final List<String> stopTokens;
  final int contextSize;
  final int batchSize;
  final int? threads;
  final GenerationOptions options;
  final String? loraPath;
  final double loraScale;
}

/// Response from worker.
// ignore: unused_element
abstract class _WorkerResponse {}

/// Model initialized successfully.
// ignore: unused_element
class _ModelInitializedResponse extends _WorkerResponse {
  _ModelInitializedResponse();
}

/// Model initialization failed.
// ignore: unused_element
class _ModelInitErrorResponse extends _WorkerResponse {
  _ModelInitErrorResponse(this.error);
  final String error;
}

/// Inference token from worker.
// ignore: unused_element
class _InferenceTokenResponse extends _WorkerResponse {
  _InferenceTokenResponse({
    required this.requestId,
    required this.token,
  });
  final int requestId;
  final String token;
}

/// Inference complete.
// ignore: unused_element
class _InferenceCompleteResponse extends _WorkerResponse {
  _InferenceCompleteResponse({
    required this.requestId,
    required this.promptTokens,
    required this.generatedTokens,
  });
  final int requestId;
  final int promptTokens;
  final int generatedTokens;
}

/// Inference error.
// ignore: unused_element
class _InferenceErrorResponse extends _WorkerResponse {
  _InferenceErrorResponse({
    required this.requestId,
    required this.error,
  });
  final int requestId;
  final String error;
}

/// Worker isolate for model reuse.
///
/// This worker keeps a model loaded and processes inference requests
/// through a queue, allowing the model to be reused across multiple requests.
///
/// Note: This is a foundation for future optimization. The current implementation
/// still uses per-request isolates, but this provides the structure for
/// implementing model reuse.
class IsolateWorker {
  IsolateWorker._();

  /// Creates a new worker isolate.
  ///
  /// The worker will keep the model loaded and process requests sequentially.
  static Future<IsolateWorker> create({
    required String modelPath,
    required int nGpuLayers,
  }) async {
    // TODO: Implement persistent worker isolate
    // For now, this is a placeholder that documents the intended architecture
    throw UnimplementedError(
      'IsolateWorker is not yet fully implemented. '
      'The current implementation uses per-request isolates for isolation.',
    );
  }

  /// Sends an inference request to the worker.
  Stream<_WorkerResponse> runInference({
    required String prompt,
    required List<String> stopTokens,
    required int contextSize,
    required int batchSize,
    int? threads,
    required GenerationOptions options,
    String? loraPath,
    double loraScale = 1.0,
  }) {
    // TODO: Implement request queue and processing
    throw UnimplementedError('IsolateWorker.runInference not yet implemented');
  }

  /// Disposes the worker and unloads the model.
  void dispose() {
    // TODO: Implement cleanup
  }
}
