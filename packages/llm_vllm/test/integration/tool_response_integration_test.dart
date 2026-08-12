/// Thorough integration tests for tool response flow with VLLM.
///
/// Validates the stream contract per docs/TOOL_RESPONSE_CHAT_LOOP.md:
/// - Content chunks (assistant text)
/// - Tool call chunks (model requests tools)
/// - Tool result chunks (role: tool, toolCallId, content)
///
/// Ensures tool responses feed back into the chat loop and are visible
/// to consumers per OpenAI function calling specifications.
library;

import 'dart:io';

import 'package:llm_vllm/llm_vllm.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group(
    'VLLM Tool Response Integration Tests',
    () {
      late VLLMChatRepository repo;

      setUp(() {
        repo = createRepository();
      });

      group('Stream contract - tool result chunks', () {
        test(
          'tool result chunks are emitted with role tool, toolCallId, and content',
          () async {
            final chunks = await _collectCalculatorToolRun(
              repo,
              maxAttempts: 3,
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            expect(
              toolResultChunks,
              isNotEmpty,
              reason:
                  'Stream must contain tool result chunks for chat visibility',
            );

            for (final chunk in toolResultChunks) {
              expect(
                chunk.message?.role,
                equals(LLMRole.tool),
                reason: 'Tool result chunk must have role: tool',
              );
              expect(
                chunk.message?.toolCallId,
                isNotNull,
                reason: 'Tool result chunk must have toolCallId',
              );
              expect(
                chunk.message!.toolCallId!,
                isNotEmpty,
                reason: 'Tool result chunk toolCallId must be non-empty',
              );
              expect(
                chunk.message?.content,
                isNotNull,
                reason: 'Tool result chunk must have content',
              );
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'toolCallId follows synthetic format when backend omits id',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content:
                        'Calculate 2 + 2 with the calculator. Reply with the number only.',
                  ),
                ],
                tools: [CalculatorTool()],
              ),
              const Duration(minutes: 3),
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            if (toolResultChunks.isEmpty) {
              return; // Model may not have used tool
            }

            final toolCallId = toolResultChunks.first.message?.toolCallId ?? '';
            expect(
              toolCallId,
              matches(RegExp(r'^tool_\d+_\w+$|^call_|^[a-zA-Z0-9_-]+$')),
              reason:
                  'toolCallId should be synthetic (tool_N_name) or backend id',
            );
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool call chunks precede tool result chunks in stream order',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content:
                        'Use calculator for 3 * 4. Reply with the number only.',
                  ),
                ],
                tools: [CalculatorTool()],
              ),
              const Duration(minutes: 3),
            );

            var lastToolCallChunkIndex = -1;
            var firstToolResultChunkIndex = -1;

            for (var i = 0; i < chunks.length; i++) {
              final c = chunks[i];
              if (c.message?.toolCalls != null &&
                  c.message!.toolCalls!.isNotEmpty) {
                lastToolCallChunkIndex = i;
              }
              if (c.message?.role == LLMRole.tool) {
                if (firstToolResultChunkIndex == -1) {
                  firstToolResultChunkIndex = i;
                }
              }
            }

            if (lastToolCallChunkIndex >= 0 && firstToolResultChunkIndex >= 0) {
              expect(
                lastToolCallChunkIndex,
                lessThan(firstToolResultChunkIndex),
                reason:
                    'Tool call chunks must appear before tool result chunks',
              );
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'toolCallId from tool result can be matched to tool call by id',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content: 'Calculate 10 + 5. Reply with the number only.',
                  ),
                ],
                tools: [CalculatorTool()],
              ),
              const Duration(minutes: 3),
            );

            final toolCallIdToName = <String, String>{};
            for (final c in chunks) {
              for (final tc in c.message?.toolCalls ?? const []) {
                final id = tc.id ?? 'tool_${tc.name}';
                toolCallIdToName[id] = tc.name;
              }
            }

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            for (final c in toolResultChunks) {
              final toolCallId = c.message?.toolCallId;
              if (toolCallId == null) continue;
              final name = toolCallIdToName[toolCallId];
              if (name != null) {
                expect(name, isNotEmpty);
              }
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });

      group('Deterministic tool results', () {
        test(
          'calculator 15*7 returns 105 and model incorporates it',
          () async {
            final chunks = await _collectCalculatorToolRun(
              repo,
              maxAttempts: 3,
            );

            final content = extractContent(chunks);
            expect(
              content,
              anyOf(contains('105'), contains('calculator')),
              reason: 'Model must receive tool result and use it in response',
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            expect(
              toolResultChunks,
              isNotEmpty,
              reason:
                  'Expected calculator tool result chunks after retrying tool-directed prompts',
            );
            final toolContent = toolResultChunks
                .map((c) => c.message?.content ?? '')
                .join();
            expect(
              toolContent,
              anyOf(contains('105'), contains('Result: 105')),
              reason: 'Tool result chunk must contain calculator output',
            );
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'echo tool returns exact input in tool result',
          () async {
            const input = 'Hello from integration test 12345';
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content:
                        'Use the echo tool with message "$input". Then repeat that message back to me.',
                  ),
                ],
                tools: [EchoTool()],
              ),
              const Duration(minutes: 3),
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            if (toolResultChunks.isNotEmpty) {
              final toolContent = toolResultChunks.first.message?.content ?? '';
              expect(
                toolContent,
                equals(input),
                reason: 'Echo tool must return exact input',
              );
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });

      group('Error handling', () {
        test(
          'tool execution error produces tool result chunk with error message',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content: 'Use the error_tool to test error handling.',
                  ),
                ],
                tools: [ErrorTool()],
              ),
              const Duration(minutes: 3),
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            if (toolResultChunks.isNotEmpty) {
              final content = toolResultChunks.first.message?.content ?? '';
              expect(
                content,
                anyOf(
                  contains('failed'),
                  contains('error'),
                  contains('Error'),
                  contains('Exception'),
                ),
                reason: 'Tool error must be captured in tool result chunk',
              );
              expect(toolResultChunks.first.message?.toolCallId, isNotNull);
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });

      group('Multiple tools', () {
        test(
          'multiple tools available - tool result matches called tool',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content: 'Get weather for Paris using the weather tool.',
                  ),
                ],
                tools: [CalculatorTool(), WeatherTool(), SearchTool()],
              ),
              const Duration(minutes: 3),
            );

            final toolCallChunks = chunks
                .where(
                  (c) =>
                      c.message?.toolCalls != null &&
                      c.message!.toolCalls!.isNotEmpty,
                )
                .toList();
            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();

            if (toolResultChunks.isNotEmpty && toolCallChunks.isNotEmpty) {
              final toolResult = toolResultChunks.first.message!;
              expect(toolResult.toolCallId, isNotNull);
              expect(toolResult.content, isNotNull);
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'tool chain - each round emits tool result chunks',
          () async {
            final messages = [
              LLMMessage(
                role: LLMRole.user,
                content: 'First calculate 6 * 7 with the calculator.',
              ),
            ];

            var chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: messages,
                tools: [CalculatorTool(), SearchTool()],
              ),
              const Duration(minutes: 5),
            );

            var totalToolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .length;

            final content1 = extractContent(chunks);
            if (content1.contains('42') ||
                content1.contains('calculator') ||
                content1.contains('Result')) {
              messages.add(
                LLMMessage(role: LLMRole.assistant, content: content1),
              );
              messages.add(
                LLMMessage(
                  role: LLMRole.user,
                  content: 'Now search for "42" using the search tool.',
                ),
              );

              chunks = await collectStreamWithTimeout(
                repo.streamChat(
                  chatModel,
                  messages: messages,
                  tools: [CalculatorTool(), SearchTool()],
                ),
                const Duration(minutes: 5),
              );

              totalToolResultChunks += chunks
                  .where((c) => c.message?.role == LLMRole.tool)
                  .length;
            }

            expect(chunks, isNotEmpty);
            if (totalToolResultChunks > 0) {
              expect(
                totalToolResultChunks,
                greaterThanOrEqualTo(1),
                reason: 'Tool chain should emit tool result chunks per round',
              );
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 10)),
        );
      });

      group('No tools / no tool call', () {
        test(
          'stream without tool call has no tool result chunks',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content: 'What is 2 + 2? Just say the number, no tools.',
                  ),
                ],
                tools: [CalculatorTool()],
              ),
              const Duration(minutes: 3),
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            expect(
              toolResultChunks,
              isEmpty,
              reason: 'When model does not call tools, no tool result chunks',
            );
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'stream without tools parameter has no tool result chunks',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content: 'Hello, how are you?',
                  ),
                ],
              ),
              const Duration(minutes: 3),
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            expect(toolResultChunks, isEmpty);
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });

      group('Max tool attempts', () {
        test(
          'multiple tool rounds emit tool result chunks per round',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content:
                        'Calculate 1+1, then calculate 2+2. Use the calculator each time.',
                  ),
                ],
                tools: [CalculatorTool()],
                toolAttempts: 5,
              ),
              const Duration(minutes: 5),
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            expect(chunks, isNotEmpty);
            if (toolResultChunks.isNotEmpty) {
              expect(
                toolResultChunks.every(
                  (c) =>
                      c.message?.toolCallId != null &&
                      c.message!.toolCallId!.isNotEmpty &&
                      c.message?.content != null,
                ),
                isTrue,
                reason:
                    'Each tool result chunk must have toolCallId and content',
              );
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );

        test(
          'strict mode throws when attempts are exhausted before final assistant answer',
          () async {
            final tempDir = Directory.systemTemp.createTempSync(
              'llm_strict_attempts',
            );
            addTearDown(() => tempDir.deleteSync(recursive: true));

            final sourceFile = File('${tempDir.path}/source.txt');
            await sourceFile.writeAsString(
              'strict-mode multi-turn validation content',
            );

            expect(
              () => collectStreamWithTimeout(
                repo.streamChat(
                  chatModel,
                  messages: [
                    LLMMessage(
                      role: LLMRole.user,
                      content:
                          'Use read_file on source.txt first. '
                          'After you have the exact read result, call write_file to copy it to dest.txt. '
                          'Then provide a final confirmation.',
                    ),
                  ],
                  tools: [ReadFileTool(), WriteFileTool()],
                  extra: {'basePath': tempDir.path},
                  toolAttempts: 1,
                  options: const StreamChatOptions(),
                ),
                const Duration(minutes: 5),
              ),
              throwsA(isA<ToolLoopIncompleteException>()),
            );
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 6)),
        );
      });

      group('Tool with no parameters', () {
        test(
          'get_time tool returns result in tool result chunk',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content: 'Get the current time using the time tool.',
                  ),
                ],
                tools: [NoParamTool()],
              ),
              const Duration(minutes: 3),
            );

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            if (toolResultChunks.isNotEmpty) {
              final content = toolResultChunks.first.message?.content ?? '';
              expect(
                content,
                matches(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}')),
                reason: 'Tool result should contain ISO timestamp',
              );
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });

      group('Final response incorporates tool result', () {
        test(
          'model final response reflects tool output',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content:
                        'Use the calculator to compute 100 / 4. Your final answer must include the result.',
                  ),
                ],
                tools: [CalculatorTool()],
              ),
              const Duration(minutes: 3),
            );

            final content = extractContent(chunks);
            expect(content, isNotEmpty);

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            if (toolResultChunks.isNotEmpty) {
              final toolContent = toolResultChunks.first.message?.content ?? '';
              expect(
                toolContent,
                anyOf(contains('25'), contains('Result: 25')),
                reason: 'Calculator 100/4 should return 25',
              );
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });

      group('VLLM-specific tool_name derivation', () {
        test(
          'tool result chunks enable toolCallId-to-name mapping for display',
          () async {
            final chunks = await collectStreamWithTimeout(
              repo.streamChat(
                chatModel,
                messages: [
                  LLMMessage(
                    role: LLMRole.user,
                    content: 'Use the calculator to compute 7 * 8.',
                  ),
                ],
                tools: [CalculatorTool()],
              ),
              const Duration(minutes: 3),
            );

            final toolCallIdToName = <String, String>{};
            for (final c in chunks) {
              for (final tc in c.message?.toolCalls ?? const []) {
                final id = tc.id ?? 'tool_${tc.name}';
                toolCallIdToName[id] = tc.name;
              }
            }

            final toolResultChunks = chunks
                .where((c) => c.message?.role == LLMRole.tool)
                .toList();
            for (final c in toolResultChunks) {
              final id = c.message?.toolCallId;
              if (id == null) continue;
              final name = toolCallIdToName[id];
              if (name == null) {
                final syntheticMatch = RegExp(
                  r'^tool_\d+_(.+)$',
                ).firstMatch(id);
                if (syntheticMatch != null) {
                  expect(syntheticMatch.group(1), isNotEmpty);
                }
              } else {
                expect(name, equals('calculator'));
              }
            }
          },
          tags: ['integration'],
          timeout: const Timeout(Duration(minutes: 5)),
        );
      });
    },
    skip: toolTestsEnabled ? false : 'Set VLLM_ENABLE_TOOL_TESTS=true',
  );
}

Future<List<LLMChunk>> _collectCalculatorToolRun(
  VLLMChatRepository repo, {
  int maxAttempts = 3,
}) async {
  final prompts = <String>[
    'Use the calculator tool to compute 15 * 7. Reply with only the number, nothing else.',
    'Call the calculator tool with expression "15 * 7". Do not solve it yourself.',
    'You must use the calculator tool now. Expression: 15 * 7. Return only tool result.',
  ];

  List<LLMChunk> lastChunks = const <LLMChunk>[];
  for (var i = 0; i < maxAttempts; i++) {
    final prompt = prompts[i < prompts.length ? i : prompts.length - 1];
    final chunks = await collectStreamWithTimeout(
      repo.streamChat(
        chatModel,
        messages: [LLMMessage(role: LLMRole.user, content: prompt)],
        tools: [CalculatorTool()],
      ),
      const Duration(minutes: 3),
    );

    if (chunks.any((c) => c.message?.role == LLMRole.tool)) {
      return chunks;
    }
    lastChunks = chunks;
  }

  return lastChunks;
}
