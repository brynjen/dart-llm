part of 'llamacpp_chat_repository.dart';

Future<List<LLMEmbedding>> _embedImpl(
  LlamaCppChatRepository repo,
  String model,
  List<String> messages,
  Map<String, dynamic> options,
) async {
  if (repo._model == null) {
    throw const ModelLoadException(
      'No model loaded. Call loadModel() first or use LlamaCppChatRepository.withModel().',
    );
  }

  if (messages.isEmpty) {
    throw const LLMApiException(
      'Messages list cannot be empty',
      statusCode: 400,
    );
  }

  final receivePort = ReceivePort();
  Isolate isolate;
  try {
    isolate = await Isolate.spawn(
      runEmbedding,
      EmbeddingRequest(
        sendPort: receivePort.sendPort,
        modelPath: repo._model!.path,
        messages: messages,
        contextSize: repo.contextSize,
        batchSize: repo.batchSize,
        threads: repo.threads,
        nGpuLayers: repo.nGpuLayers,
      ),
    );
  } catch (e) {
    receivePort.close();
    LlamaCppChatRepository._log.severe('Failed to spawn embedding isolate: $e');
    throw InferenceException(
      message: 'Failed to spawn embedding isolate: $e',
      details: 'Model: ${repo._model?.path ?? "unknown"}',
    );
  }

  try {
    final results = <LLMEmbedding>[];
    await for (final message in receivePort) {
      if (message is EmbeddingResult) {
        results.add(message.embedding);
      } else if (message is EmbeddingError) {
        throw InferenceErrorTranslator.translateEmbeddingError(
          message.error,
          modelPath: repo._model?.path,
          contextSize: repo.contextSize,
          batchSize: repo.batchSize,
        );
      } else if (message is EmbeddingComplete) {
        break;
      }
    }
    return results;
  } finally {
    receivePort.close();
    isolate.kill();
  }
}
