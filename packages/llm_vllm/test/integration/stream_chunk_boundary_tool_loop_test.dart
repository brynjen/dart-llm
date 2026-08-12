/// Integration test for stream chunk boundary resilience in tool loops.
///
/// Follows the standard integration setup using test_helpers and a live VLLM
/// endpoint, like the rest of the integration suite.
library;

import 'dart:io';

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group(
    'VLLM Integration Tests - Stream Chunk Boundary Regression',
    () {
      late VLLMChatRepository repo;

      setUp(() {
        repo = createRepository();
      });

      test(
        'read->write tool loop emits tool results and completes with final assistant text',
        () async {
          final tempDir = Directory.systemTemp.createTempSync(
            'llm_chunk_boundary_loop',
          );
          addTearDown(() => tempDir.deleteSync(recursive: true));

          final sourceFile = File('${tempDir.path}/source.txt');
          await sourceFile.writeAsString(
            'Hello from chunk-boundary regression',
          );
          final destFile = File('${tempDir.path}/dest.txt');

          final chunks = await collectStreamWithTimeout(
            repo.streamChat(
              chatModel,
              messages: [
                LLMMessage(
                  role: LLMRole.user,
                  content:
                      'Read source.txt using read_file. Then write exactly that content to dest.txt '
                      'using write_file. Finally confirm completion.',
                ),
              ],
              tools: [ReadFileTool(), WriteFileTool()],
              extra: {'basePath': tempDir.path},
              toolAttempts: 5,
            ),
            const Duration(minutes: 5),
          );

          expect(chunks, isNotEmpty);
          expect(
            chunks.any((chunk) => chunk.done == true),
            isTrue,
            reason:
                'Expected stream to complete with at least one done=true chunk',
          );

          final toolResultChunks = chunks
              .where((chunk) => chunk.message?.role == LLMRole.tool)
              .toList();
          expect(
            toolResultChunks.length,
            greaterThanOrEqualTo(2),
            reason:
                'Expected at least read_file and write_file tool result chunks',
          );

          final toolResultContent = toolResultChunks
              .map((chunk) => chunk.message?.content ?? '')
              .join('\n');
          expect(
            toolResultContent,
            contains('Hello from chunk-boundary regression'),
            reason: 'Expected read_file result content in tool result stream',
          );
          expect(
            toolResultContent,
            anyOf(contains('Wrote'), contains('dest.txt')),
            reason: 'Expected write_file confirmation in tool result stream',
          );

          final toolCallNames = chunks
              .expand(
                (chunk) => chunk.message?.toolCalls ?? const <LLMToolCall>[],
              )
              .map((toolCall) => toolCall.name)
              .toSet();
          expect(toolCallNames.contains('read_file'), isTrue);
          expect(toolCallNames.contains('write_file'), isTrue);

          final assistantContent = extractContent(chunks).trim();
          expect(
            assistantContent,
            isNotEmpty,
            reason: 'Expected non-empty assistant output after tool loop',
          );

          expect(destFile.existsSync(), isTrue);
          expect(
            destFile.readAsStringSync(),
            contains('Hello from chunk-boundary regression'),
          );
        },
        tags: ['integration'],
        timeout: const Timeout(Duration(minutes: 6)),
      );
    },
    skip: toolTestsEnabled ? false : 'Set VLLM_ENABLE_TOOL_TESTS=true',
  );
}
