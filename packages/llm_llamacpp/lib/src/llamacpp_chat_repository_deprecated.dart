part of 'llamacpp_chat_repository.dart';

void _initializeBackendImpl(LlamaCppChatRepository repo) {
  if (repo._backendInitialized) return;

  final lib = loadLlamaLibrary();
  repo._bindings = LlamaBindings(lib);

  final backendsLoaded = BackendInitializer.loadBackends(lib);
  if (!backendsLoaded) {
    LlamaCppChatRepository._log.warning(
      'Backend loading failed. This may cause model loading to fail on Android with dynamic backend loading enabled.',
    );
  }

  repo._bindings!.llama_backend_init();
  repo._backendInitialized = true;
}

Future<void> _loadModelImpl(
  LlamaCppChatRepository repo,
  String modelPath, {
  ModelLoadOptions options = const ModelLoadOptions(),
}) async {
  _initializeBackendImpl(repo);

  if (repo._model != null && repo._ownsModel) {
    repo._model!.dispose();
    repo._model = null;
  }

  repo._model = LlamaCppModel.load(
    modelPath,
    repo._bindings!,
    nGpuLayers: options.nGpuLayers,
    useMemoryMap: options.useMemoryMap,
    useMemoryLock: options.useMemoryLock,
    vocabOnly: options.vocabOnly,
  );
}

void _unloadModelImpl(LlamaCppChatRepository repo) {
  if (repo._model != null && repo._ownsModel) {
    repo._model!.dispose();
    repo._model = null;
  }
}
