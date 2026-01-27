part of 'persistent_inference_isolate.dart';

class _InferenceRequestMessage {
  _InferenceRequestMessage({
    required this.requestId,
    required this.modelPath,
    required this.prompt,
    required this.stopTokens,
    required this.contextSize,
    required this.batchSize,
    required this.nGpuLayers,
    required this.options,
    this.threads,
    this.loraPath,
    this.loraScale = 1.0,
    this.messages,
  });

  final int requestId;
  final String modelPath;
  final String prompt;
  final List<IsolateMessage>? messages;
  final List<String> stopTokens;
  final int contextSize;
  final int batchSize;
  final int? threads;
  final int nGpuLayers;
  final GenerationOptions options;
  final String? loraPath;
  final double loraScale;
}

/// Internal response wrapper for sending data back from the helper isolate.
class _IsolateResponse {
  _IsolateResponse({
    required this.requestId,
    required this.payload,
    required this.isComplete,
  });

  final int requestId;
  final dynamic payload;
  final bool isComplete;
}
