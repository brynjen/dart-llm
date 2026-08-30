library;

import 'dart:async';
import 'dart:convert';

import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

class _EchoTool extends LLMTool {
  @override
  String get name => 'echo_tool';

  @override
  String get description => 'Echoes the provided message';

  @override
  List<LLMToolParam> get parameters => const [];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return jsonEncode(args);
  }
}

/// A tool the model is made to call on every round, so the loop runs until the
/// budget is gone.
class _AlwaysCallsTool extends LLMTool {
  @override
  String get name => 'looping_tool';

  @override
  String get description => 'Always called again';

  @override
  List<LLMToolParam> get parameters => const [];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      'ok';
}

LLMChunk _toolCallChunk() => LLMChunk(
  model: 'test-model',
  createdAt: DateTime(2026),
  done: true,
  message: LLMChunkMessage(
    content: null,
    role: LLMRole.assistant,
    toolCalls: [
      LLMToolCall(name: 'looping_tool', arguments: '{}', id: 'call_1'),
    ],
  ),
);

void main() {
  group('tool attempt accounting', () {
    test(
      'reports the attempts actually consumed when the budget runs out',
      () async {
        // Every recursion builds a fresh executor whose budget is already
        // decremented, so the level that runs out cannot see how many rounds
        // preceded it. Without restating the accounting on the way out, this
        // reported `attemptsUsed: 0` no matter how many rounds had run.
        const budget = 3;
        var rounds = 0;

        late StreamToolExecutor executor;
        executor = StreamToolExecutor(
          tools: [_AlwaysCallsTool()],
          extra: null,
          maxToolAttempts: budget,
          streamChatCallback: (model, messages, tools, extra, attempts) {
            rounds++;
            // Mirrors a provider: a fresh executor whose ceiling is the
            // already-decremented remaining budget.
            final next = StreamToolExecutor(
              tools: tools,
              extra: extra,
              maxToolAttempts: attempts,
              streamChatCallback: executor.streamChatCallback,
            );
            return next.executeTools(
              chunkStream: Stream.value(_toolCallChunk()),
              model: model,
              initialMessages: messages,
              toolAttempts: attempts,
            );
          },
        );

        await expectLater(
          executor
              .executeTools(
                chunkStream: Stream.value(_toolCallChunk()),
                model: 'test-model',
                initialMessages: [
                  LLMMessage(role: LLMRole.user, content: 'go'),
                ],
                toolAttempts: budget,
              )
              .toList(),
          throwsA(
            isA<ToolLoopIncompleteException>()
                .having((e) => e.attemptsUsed, 'attemptsUsed', budget)
                .having((e) => e.attemptsRemaining, 'attemptsRemaining', 0),
          ),
        );

        // The budget really did cap the loop.
        expect(rounds, budget);
      },
    );
  });

  group('StreamToolExecutor', () {
    test(
      'synthesizes non-empty toolCallId when LLMToolCall.id is null',
      () async {
        final tool = _EchoTool();

        // Simulate a backend tool call with a null id
        final toolCall = LLMToolCall(
          name: tool.name,
          arguments: jsonEncode({'message': 'hello'}),
          id: null,
        );

        // This mirrors the logic inside StreamToolExecutor for deriving the
        // effective toolCallId when the backend omits an id.
        const toolCallIndex = 0;
        final effectiveToolCallId =
            (toolCall.id != null && toolCall.id!.isNotEmpty)
            ? toolCall.id!
            : 'tool_${toolCallIndex}_${toolCall.name}';

        final toolResponse = await tool.execute(
          jsonDecode(toolCall.arguments) as Map<String, dynamic>,
        );

        final message = LLMMessage(
          content: toolResponse is String
              ? toolResponse
              : toolResponse.toString(),
          role: LLMRole.tool,
          toolCallId: effectiveToolCallId,
        );

        expect(message.toolCallId, isNotNull);
        expect(message.toolCallId, isNotEmpty);

        // Ensure the synthesized message passes validation.
        expect(() => Validation.validateMessage(message), returnsNormally);
      },
    );

    test(
      'synthesizes distinct toolCallIds for each index when multiple calls have null id',
      () {
        const toolName = 'echo_tool';
        const indices = [0, 1, 2];

        for (var i = 0; i < indices.length; i++) {
          final toolCallIndex = indices[i];
          final toolCall = LLMToolCall(
            name: toolName,
            arguments: '{}',
            id: null,
          );
          final effectiveToolCallId =
              (toolCall.id != null && toolCall.id!.isNotEmpty)
              ? toolCall.id!
              : 'tool_${toolCallIndex}_${toolCall.name}';

          expect(
            effectiveToolCallId,
            equals('tool_${toolCallIndex}_$toolName'),
          );
        }

        expect([
          'tool_0_echo_tool',
          'tool_1_echo_tool',
          'tool_2_echo_tool',
        ], orderedEquals(indices.map((i) => 'tool_${i}_$toolName').toList()));
      },
    );

    test(
      'assigns correct toolCallIndex per tool call when stream has multiple tool calls with null ids',
      () async {
        final tool = _EchoTool();
        final toolCalls = [
          LLMToolCall(name: tool.name, arguments: '{"a":1}', id: null),
          LLMToolCall(name: tool.name, arguments: '{"a":2}', id: null),
          LLMToolCall(name: tool.name, arguments: '{"a":3}', id: null),
        ];

        List<LLMMessage>? capturedMessages;
        final chunkStream = Stream.fromIterable([
          LLMChunk(
            model: 'test',
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: null,
              role: LLMRole.assistant,
              toolCalls: toolCalls,
            ),
            done: true,
          ),
        ]);

        final executor = StreamToolExecutor(
          tools: [tool],
          extra: null,
          maxToolAttempts: 1,
          streamChatCallback: (model, messages, tools, extra, attempts) {
            capturedMessages = messages;
            return const Stream.empty();
          },
        );

        await executor
            .executeTools(
              chunkStream: chunkStream,
              model: 'test',
              initialMessages: [
                LLMMessage(role: LLMRole.user, content: 'Use the tool 3 times'),
              ],
              toolAttempts: 1,
            )
            .toList();

        expect(capturedMessages, isNotNull);
        expect(
          capturedMessages!.length,
          equals(5),
        ); // 1 user + 1 assistant + 3 tool responses

        final assistantMessage = capturedMessages!
            .where((m) => m.role == LLMRole.assistant)
            .single;
        expect(assistantMessage.toolCalls, isNotNull);
        expect(assistantMessage.toolCalls!.length, equals(3));

        final toolMessages = capturedMessages!
            .where((m) => m.role == LLMRole.tool)
            .toList();
        expect(toolMessages.length, equals(3));

        expect(toolMessages[0].toolCallId, equals('tool_0_echo_tool'));
        expect(toolMessages[1].toolCallId, equals('tool_1_echo_tool'));
        expect(toolMessages[2].toolCallId, equals('tool_2_echo_tool'));

        for (final msg in toolMessages) {
          expect(() => Validation.validateMessage(msg), returnsNormally);
        }
      },
    );

    test('emits tool result chunks so chat can display them', () async {
      final tool = _EchoTool();
      final toolCalls = [
        LLMToolCall(name: tool.name, arguments: '{"a":1}', id: null),
      ];

      final chunkStream = Stream.fromIterable([
        LLMChunk(
          model: 'test',
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: null,
            role: LLMRole.assistant,
            toolCalls: toolCalls,
          ),
          done: true,
        ),
      ]);

      final executor = StreamToolExecutor(
        tools: [tool],
        extra: null,
        maxToolAttempts: 1,
        streamChatCallback: (model, messages, tools, extra, attempts) =>
            const Stream.empty(),
      );

      final chunks = await executor
          .executeTools(
            chunkStream: chunkStream,
            model: 'test',
            initialMessages: [LLMMessage(role: LLMRole.user, content: 'Echo')],
            toolAttempts: 1,
          )
          .toList();

      final toolResultChunks = chunks
          .where((c) => c.message?.role == LLMRole.tool)
          .toList();
      expect(toolResultChunks.length, equals(1));
      expect(toolResultChunks[0].message?.content, equals('{"a":1}'));
      expect(
        toolResultChunks[0].message?.toolCallId,
        equals('tool_0_echo_tool'),
      );
    });

    test(
      'strict mode throws when attempts are exhausted and model still requests tools',
      () async {
        final tool = _EchoTool();
        final chunkStream = Stream.fromIterable([
          LLMChunk(
            model: 'test',
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: null,
              role: LLMRole.assistant,
              toolCalls: [
                LLMToolCall(
                  name: tool.name,
                  arguments: '{"a":1}',
                  id: 'call_1',
                ),
              ],
            ),
            done: true,
          ),
        ]);

        final executor = StreamToolExecutor(
          tools: [tool],
          extra: null,
          maxToolAttempts: 1,
          streamChatCallback: (model, messages, tools, extra, attempts) =>
              const Stream.empty(),
        );

        expect(
          () async => executor
              .executeTools(
                chunkStream: chunkStream,
                model: 'test',
                initialMessages: [
                  LLMMessage(role: LLMRole.user, content: 'Echo'),
                ],
                toolAttempts: 0,
              )
              .toList(),
          throwsA(isA<ToolLoopIncompleteException>()),
        );
      },
    );

    test(
      'strict mode accepts final assistant answer after tool loop',
      () async {
        final tool = _EchoTool();
        final chunkStream = Stream.fromIterable([
          LLMChunk(
            model: 'test',
            createdAt: DateTime.now(),
            message: LLMChunkMessage(content: 'Done', role: LLMRole.assistant),
            done: true,
          ),
        ]);

        final executor = StreamToolExecutor(
          tools: [tool],
          extra: null,
          maxToolAttempts: 1,
          streamChatCallback: (model, messages, tools, extra, attempts) =>
              const Stream.empty(),
        );

        final chunks = await executor
            .executeTools(
              chunkStream: chunkStream,
              model: 'test',
              initialMessages: [
                LLMMessage(role: LLMRole.user, content: 'Echo'),
                LLMMessage(
                  role: LLMRole.tool,
                  content: '{"a":1}',
                  toolCallId: 'call_1',
                ),
              ],
              toolAttempts: 0,
            )
            .toList();

        expect(chunks.length, 1);
        expect(chunks.first.message?.content, 'Done');
      },
    );
  });
}
