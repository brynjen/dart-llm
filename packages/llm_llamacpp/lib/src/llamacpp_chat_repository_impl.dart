part of 'llamacpp_chat_repository.dart';

Stream<LLMChunk> _streamChatImpl(
  LlamaCppChatRepository repo,
  String model,
  List<LLMMessage> messages,
  bool think,
  List<LLMTool> tools,
  dynamic extra,
  StreamChatOptions? options,
  GenerationOptions? generationOptions,
) async* {
  final genOptions = generationOptions ?? const GenerationOptions();
  Validation.validateModelName(model);
  Validation.validateMessages(messages);

  final String modelPath;
  if (repo._model != null) {
    modelPath = repo._model!.path;
  } else if (repo._modelPath != null) {
    modelPath = repo._modelPath!;
  } else {
    throw const ModelLoadException(
      'No model loaded. Call loadModel() first, use LlamaCppChatRepository.withModel(), or use LlamaCppChatRepository.withModelPath().',
    );
  }

  if (repo._model != null && repo.contextSize > repo._model!.contextSizeTrain) {
    LlamaCppChatRepository._log.warning(
      'Requested context size (${repo.contextSize}) exceeds model training context size (${repo._model!.contextSizeTrain}). '
      'This may cause issues or be truncated.',
    );
  }

  final hasImages = messages.any(
    (msg) => msg.images != null && msg.images!.isNotEmpty,
  );
  if (hasImages) {
    throw VisionNotSupportedException(
      model,
      'Vision/image support is not yet fully implemented in llm_llamacpp. '
      'Vision models can be loaded and used for text inference, but image input processing requires additional multimodal bindings.',
    );
  }

  final effectiveTools = options?.tools.isNotEmpty == true
      ? options!.tools
      : tools;
  final effectiveExtra = options?.extra ?? extra;
  final effectiveToolAttempts = options?.toolAttempts;
  final currentAttempts = effectiveToolAttempts ?? repo.maxToolAttempts;

  LlamaCppChatRepository._log.fine(
    'streamChat called with ${effectiveTools.length} tools, attempt ${repo.maxToolAttempts - currentAttempts + 1}',
  );
  LlamaCppChatRepository._log.fine('Messages count: ${messages.length}');
  if (LlamaCppChatRepository._log.isLoggable(LLMLogLevel.fine)) {
    for (final msg in messages) {
      LlamaCppChatRepository._log.fine(
        '  - ${msg.role.name}: ${msg.content?.substring(0, msg.content!.length.clamp(0, 100))}...',
      );
    }
  }

  final isolateMessages = messages
      .map(
        (msg) => IsolateMessage(
          role: switch (msg.role) {
            LLMRole.system => 'system',
            LLMRole.user => 'user',
            LLMRole.assistant => 'assistant',
            LLMRole.tool => 'tool',
          },
          content: msg.content ?? '',
        ),
      )
      .toList();

  LlamaCppChatRepository._log.fine(
    'Sending ${isolateMessages.length} messages for native template formatting',
  );

  final inferenceStream = PersistentInferenceIsolate.instance.runInference(
    modelPath: modelPath,
    prompt: '',
    stopTokens: const [],
    contextSize: repo.contextSize,
    batchSize: repo.batchSize,
    threads: repo.threads,
    nGpuLayers: repo.nGpuLayers,
    options: genOptions,
    loraPath: repo._loraPath,
    loraScale: repo._loraScale,
    messages: isolateMessages,
  );

  try {
    final streamHandler = ToolCallStreamHandler(
      logger: LlamaCppChatRepository._log,
      tools: effectiveTools,
    );

    await for (final message in inferenceStream) {
      if (message is InferenceToken) {
        final result = streamHandler.processToken(message.token);
        if (result.shouldYield && result.content != null) {
          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: result.content,
              role: LLMRole.assistant,
            ),
            done: false,
          );
        }
      } else if (message is InferenceComplete) {
        LlamaCppChatRepository._log.fine(
          'Inference complete. Accumulated content (${streamHandler.accumulatedContent.length} chars)',
        );
        if (LlamaCppChatRepository._log.isLoggable(LLMLogLevel.fine)) {
          LlamaCppChatRepository._log.fine(
            '--- RESPONSE START ---\n${streamHandler.accumulatedContent}\n--- RESPONSE END ---',
          );
        }

        final remainingContent = streamHandler.finalize(
          hasTools: effectiveTools.isNotEmpty,
        );
        if (remainingContent != null) {
          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: remainingContent,
              role: LLMRole.assistant,
            ),
            done: false,
          );
        }

        final collectedToolCalls = streamHandler.collectedToolCalls;
        yield LLMChunk(
          model: model,
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: null,
            role: LLMRole.assistant,
            toolCalls: collectedToolCalls.isEmpty ? null : collectedToolCalls,
          ),
          done: true,
          promptEvalCount: message.promptTokens,
          evalCount: message.generatedTokens,
        );

        if (collectedToolCalls.isNotEmpty && effectiveTools.isNotEmpty) {
          LlamaCppChatRepository._log.info(
            'Executing ${collectedToolCalls.length} tool calls...',
          );
          if (currentAttempts > 0) {
            final workingMessages = List<LLMMessage>.from(messages);
            workingMessages.add(
              LLMMessage(
                role: LLMRole.assistant,
                content: streamHandler.accumulatedContent,
              ),
            );

            final toolMessages = await ToolExecutor.executeTools(
              collectedToolCalls,
              effectiveTools,
              effectiveExtra,
              LlamaCppChatRepository._log,
            );
            workingMessages.addAll(toolMessages);

            LlamaCppChatRepository._log.fine(
              'Continuing conversation with tool results...',
            );
            final nextOptions =
                options?.copyWith(toolAttempts: currentAttempts - 1) ??
                StreamChatOptions(
                  tools: effectiveTools,
                  extra: effectiveExtra,
                  toolAttempts: currentAttempts - 1,
                );
            yield* repo.streamChatWithGenerationOptions(
              model,
              messages: workingMessages,
              tools: effectiveTools,
              extra: effectiveExtra,
              options: nextOptions,
              generationOptions: genOptions,
            );
          } else {
            LlamaCppChatRepository._log.warning(
              'Max tool attempts reached, not continuing',
            );
          }
        }
        break;
      } else if (message is InferenceError) {
        LlamaCppChatRepository._log.severe('Inference error: ${message.error}');
        throw InferenceErrorTranslator.translateInferenceError(
          message.error,
          modelPath: repo._model?.path,
          prompt: '(${messages.length} messages)',
          contextSize: repo.contextSize,
          batchSize: repo.batchSize,
        );
      }
    }
  } finally {
    // Persistent isolate stays alive
  }
}
