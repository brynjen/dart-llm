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

  late final _ModelTrack _textTrack;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _textTrack = _ModelTrack(
      title: 'Text Chat',
      subtitle: 'LFM2.5-1.2B-Instruct (Q4_K_M)',
      sizeHint: '~731 MB \u2022 Edge-focused inference',
      repoId: 'LiquidAI/LFM2.5-1.2B-Instruct-GGUF',
      files: const ['LFM2.5-1.2B-Instruct-Q4_K_M.gguf'],
      onStateChanged: () => setState(() {}),
    );

    _checkExistingModels();
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

  Future<void> _checkExistingModels() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final dir = await _modelsDirectory;
      _textTrack.refreshLocalState(dir);
    } catch (e) {
      _errorMessage = 'Error checking models: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _download(_ModelTrack track) async {
    final dir = await _modelsDirectory;
    track.errorMessage = null;
    track.refreshLocalState(dir);

    for (final file in track.files) {
      final localPath = '$dir/$file';
      if (File(localPath).existsSync()) {
        continue;
      }

      track.isDownloading = true;
      track.statusMessage = 'Downloading $file...';
      track.progress = 0;
      track.onStateChanged();

      try {
        await for (final status in _repository.getModelStream(
          track.repoId,
          outputDir: dir,
          preferredFile: file,
        )) {
          track.statusMessage = status.message;
          if (status.progress != null) {
            track.progress = status.progress!;
          }
          if (status.stage == ModelAcquisitionStage.failed) {
            track.errorMessage = status.error ?? status.message;
          }
          track.onStateChanged();
        }
      } catch (e) {
        track.errorMessage = 'Download failed: $e';
        track.onStateChanged();
        break;
      }
    }

    track.isDownloading = false;
    track.refreshLocalState(dir);
    track.onStateChanged();
  }

  void _openTextChat() {
    final modelPath = _textTrack.primaryFilePath;
    if (modelPath == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ChatScreen(modelPath: modelPath)),
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
                const SizedBox(height: 24),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                      ? _ErrorBox(message: _errorMessage!)
                      : ListView(
                          children: [
                            _TrackCard(
                              track: _textTrack,
                              onDownload: () => _download(_textTrack),
                              onOpen: _openTextChat,
                              openLabel: 'Start Text Chat',
                              openIcon: Icons.chat,
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Running on ${Platform.operatingSystem} \u2022 ${Platform.version.split(' ').first}',
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

/// Tracks one downloadable bundle (1+ GGUF files in the same HF repo).
class _ModelTrack {
  _ModelTrack({
    required this.title,
    required this.subtitle,
    required this.sizeHint,
    required this.repoId,
    required this.files,
    required this.onStateChanged,
  });

  final String title;
  final String subtitle;
  final String sizeHint;
  final String repoId;
  final List<String> files;
  final VoidCallback onStateChanged;

  String? localDirectory;
  bool isDownloading = false;
  double progress = 0;
  String statusMessage = '';
  String? errorMessage;
  Set<String> presentFiles = const {};

  bool get isReady =>
      localDirectory != null && presentFiles.length == files.length;

  String? get primaryFilePath {
    final dir = localDirectory;
    if (dir == null || files.isEmpty) return null;
    final p = '$dir/${files.first}';
    return File(p).existsSync() ? p : null;
  }

  void refreshLocalState(String modelsDir) {
    localDirectory = modelsDir;
    presentFiles = {
      for (final f in files)
        if (File('$modelsDir/$f').existsSync()) f,
    };
    if (presentFiles.isEmpty) {
      statusMessage = 'No files downloaded yet.';
    } else if (presentFiles.length == files.length) {
      statusMessage = 'All ${files.length} file(s) ready.';
    } else {
      statusMessage =
          '${presentFiles.length}/${files.length} files downloaded. '
          'Tap to fetch the rest.';
    }
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.onDownload,
    required this.onOpen,
    required this.openLabel,
    required this.openIcon,
  });

  final _ModelTrack track;
  final VoidCallback onDownload;
  final VoidCallback onOpen;
  final String openLabel;
  final IconData openIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            track.subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          Text(
            track.sizeHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          if (track.errorMessage != null)
            _ErrorBox(message: track.errorMessage!)
          else if (track.isDownloading) ...[
            Text(track.statusMessage, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: track.progress,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(track.progress * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else
            Text(
              track.statusMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (!track.isReady)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: track.isDownloading ? null : onDownload,
                    icon: const Icon(Icons.download),
                    label: Text(
                      track.presentFiles.isEmpty
                          ? 'Download'
                          : 'Resume Download',
                    ),
                  ),
                ),
              if (track.isReady) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpen,
                    icon: Icon(openIcon),
                    label: Text(openLabel),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.outlined(
                  onPressed: track.isDownloading ? null : onDownload,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Re-download',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
