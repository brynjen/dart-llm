import 'dart:io';

import 'package:flutter/material.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path_provider/path_provider.dart';

import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LlamaCppRepository _repository = LlamaCppRepository();

  String? _modelPath;
  bool _isDownloading = false;
  bool _isLoading = false;
  double _downloadProgress = 0;
  String _statusMessage = '';
  String? _errorMessage;

  // Qwen3-0.6B: Small, efficient model
  static const _defaultRepoId = 'Qwen/Qwen3-0.6B-GGUF';
  static const _defaultFileName = 'Qwen3-0.6B-Q8_0.gguf';

  @override
  void initState() {
    super.initState();
    _checkExistingModel();
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  Future<String> get _modelsDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  Future<void> _checkExistingModel() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking for existing models...';
    });

    try {
      final dir = await _modelsDirectory;
      final modelFile = File('$dir/$_defaultFileName');

      if (await modelFile.exists()) {
        setState(() {
          _modelPath = modelFile.path;
          _statusMessage = 'Model found: $_defaultFileName';
        });
      } else {
        setState(() {
          _statusMessage = 'No model found. Download one to get started.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error checking models: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _statusMessage = 'Starting download...';
      _errorMessage = null;
    });

    try {
      final outputDir = await _modelsDirectory;
      print('[HomeScreen] Starting download:');
      print('[HomeScreen]   Repo: $_defaultRepoId');
      print('[HomeScreen]   File: $_defaultFileName');
      print('[HomeScreen]   Output: $outputDir');

      await for (final status in _repository.getModelStream(
        _defaultRepoId,
        outputDir: outputDir,
        preferredFile: _defaultFileName,
      )) {
        print('[HomeScreen] Status: ${status.stage.name} - ${status.message}');
        if (status.progress != null) {
          print('[HomeScreen]   Progress: ${(status.progress! * 100).toStringAsFixed(1)}%');
        }
        if (status.error != null) {
          print('[HomeScreen]   Error: ${status.error}');
        }
        
        setState(() {
          _statusMessage = status.message;
          if (status.progress != null) {
            _downloadProgress = status.progress!;
          }
          if (status.isComplete && status.modelPath != null) {
            _modelPath = status.modelPath;
            print('[HomeScreen]   Model path: ${status.modelPath}');
          }
          if (status.stage == ModelAcquisitionStage.failed) {
            _errorMessage = status.error ?? status.message;
          }
        });
      }

      setState(() {
        _statusMessage = 'Download complete!';
      });
      print('[HomeScreen] Download completed successfully');
    } catch (e, stackTrace) {
      print('[HomeScreen] Download exception: $e');
      print('[HomeScreen] Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Download failed: $e';
        _statusMessage = '';
      });
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  void _openChat() {
    if (_modelPath == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(modelPath: _modelPath!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surface.withValues(alpha: 0.8),
              theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.memory,
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'llama.cpp',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Local LLM Inference',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Model Card
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Model',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Qwen3-0.6B (Q8_0)',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          '~800 MB • Efficient inference',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Status area - expandable and scrollable
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isLoading)
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                else if (_errorMessage != null)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          color: theme.colorScheme.error,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: TextStyle(
                                              color: theme
                                                  .colorScheme
                                                  .onErrorContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (_isDownloading) ...[
                                  // Download Progress
                                  Text(
                                    _statusMessage,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: _downloadProgress,
                                      minHeight: 8,
                                      backgroundColor: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ] else if (_modelPath != null) ...[
                                  // Model Ready
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Model Ready',
                                                style: theme
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              Text(
                                                _modelPath!.split('/').last,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: 0.7,
                                                          ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  // No Model
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.download_rounded,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _statusMessage.isEmpty
                                                ? 'Download a model to get started'
                                                : _statusMessage,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.7),
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Actions
                        Row(
                          children: [
                            if (_modelPath == null && !_isDownloading)
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _downloadModel,
                                  icon: const Icon(Icons.download),
                                  label: const Text('Download Model'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),
                            if (_modelPath != null) ...[
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _openChat,
                                  icon: const Icon(Icons.chat),
                                  label: const Text('Start Chat'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton.outlined(
                                onPressed: _downloadModel,
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Re-download model',
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Platform info
                Center(
                  child: Text(
                    'Running on ${Platform.operatingSystem} • ${Platform.version.split(' ').first}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
