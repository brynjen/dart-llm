/// Integration tests for multi-turn tool calling in llm_vllm.
///
/// Verifies that the model can chain tool calls across turns: e.g. read a file,
/// then write to another file based on the read content (or write to the same file).
/// This uses the StreamToolExecutor's automatic loop: after each tool round,
/// it feeds the tool results back and continues the conversation.
library;

import 'dart:io';

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group(
    'VLLM Integration Tests - Multi-Turn Tool Calling',
    () {
      late VLLMChatRepository repo;

      setUp(() {
        repo = createRepository();
      });

      group('Read then write flow', () {
        test(
          'model reads file then writes based on content in single streamChat call',
          () async {
            final tempDir = Directory.systemTemp.createTempSync(
              'llm_multi_turn',
            );
            addTearDown(() => tempDir.deleteSync(recursive: true));

            final sourceFile = File('${tempDir.path}/source.txt');
            await sourceFile.writeAsString('Hello from multi-turn test');

            final destFile = File('${tempDir.path}/dest.txt');

            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content:
                    'Read the file at source.txt. Then write the exact content you read to dest.txt. '
                    'Use the read_file tool first with path "source.txt", then use write_file with path "dest.txt" and the content you read.',
              ),
            ];

            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [ReadFileTool(), WriteFileTool()],
                extra: {'basePath': tempDir.path},
                toolAttempts: 5,
              ),
              const Duration(minutes: 5),
            );

            expect(chunks, isNotEmpty);

            // Verify we had at least one read_file tool result
            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            expect(
              toolResultChunks.length,
              greaterThanOrEqualTo(2),
              reason:
                  'Multi-turn: expect read_file result + write_file result (at least 2 tool rounds)',
            );

            // Verify tool results: first should contain file content, second write confirmation
            final toolContents = toolResultChunks
                .map((c) => c.message?.content ?? '')
                .toList();
            expect(
              toolContents.any(
                (c) =>
                    c.contains('Hello from multi-turn test') ||
                    c.contains('Hello from multi-turn'),
              ),
              isTrue,
              reason: 'read_file tool should return source file content',
            );
            expect(
              toolContents.any(
                (c) =>
                    c.contains('Wrote') ||
                    c.contains('bytes') ||
                    c.contains('dest'),
              ),
              isTrue,
              reason: 'write_file tool should confirm write',
            );

            // Verify dest.txt was written with the expected content
            expect(destFile.existsSync(), isTrue);
            final written = destFile.readAsStringSync();
            expect(
              written,
              contains('Hello from multi-turn'),
              reason: 'dest.txt should contain content from source.txt',
            );
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });
    },
    skip: toolTestsEnabled ? false : 'Set VLLM_ENABLE_TOOL_TESTS=true',
  );
}
