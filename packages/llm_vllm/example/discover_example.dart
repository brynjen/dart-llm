/// Discovers what a vLLM deployment offers via [VLLMRepository.describe]:
/// served model and context window, probed capabilities, and the server's
/// accepted request parameters diffed against the bundled snapshot.
///
/// ```bash
/// dart run example/discover_example.dart http://192.168.0.74:8000 [more urls...]
/// ```
///
/// Defaults to `http://localhost:8000` when no URLs are given.
library;

import 'dart:io';

import 'package:llm_vllm/llm_vllm.dart';

Future<void> main(List<String> args) async {
  final urls = args.isEmpty ? ['http://localhost:8000'] : args;
  for (final url in urls) {
    final probe = VLLMRepository(baseUrl: url);
    try {
      _print(await probe.describe());
    } finally {
      probe.close();
    }
    stdout.writeln();
  }
}

void _print(VLLMDeploymentInfo info) {
  stdout.writeln('=== ${info.baseUrl} ===');
  if (!info.reachable) {
    stdout.writeln('  unreachable: ${info.error}');
    return;
  }
  if (info.models.isEmpty) {
    stdout.writeln('  server is up but serves no models');
    return;
  }

  for (final model in info.models) {
    stdout.writeln('  model:            ${model.id}');
    stdout.writeln(
      '  context window:   '
      '${model.maxModelLen != null ? '${model.maxModelLen} tokens' : 'not reported'}',
    );
    if (model.ownedBy != null) {
      stdout.writeln('  owned by:         ${model.ownedBy}');
    }
    final capabilities = info.capabilities[model.id];
    if (capabilities != null) {
      stdout.writeln(
        '  capabilities:     '
        'tools=${capabilities.tools} '
        'thinking=${capabilities.thinking} '
        'embeddings=${capabilities.embeddings} '
        'structuredOutput=${capabilities.structuredOutput}',
      );
    }
  }

  final params = info.supportedParams;
  if (params == null) {
    stdout.writeln(
      '  request schema:   /openapi.json not readable — '
      'validation falls back to the vLLM 0.27.1 snapshot',
    );
    return;
  }
  final added = params.difference(knownVllmChatParams);
  final removed = knownVllmChatParams.difference(params);
  stdout.writeln('  request schema:   ${params.length} parameters');
  if (added.isNotEmpty) {
    stdout.writeln(
      '    not in snapshot: ${(added.toList()..sort()).join(', ')}',
    );
  }
  if (removed.isNotEmpty) {
    stdout.writeln(
      '    snapshot-only:   ${(removed.toList()..sort()).join(', ')}',
    );
  }
  if (added.isEmpty && removed.isEmpty) {
    stdout.writeln('    matches the bundled vLLM 0.27.1 snapshot exactly');
  }
}
