library;

import 'dart:convert';

import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

import 'mock_llm_chat_repository.dart';

class _EchoTool extends LLMTool {
  @override
  String get name => 'echo_tool';

  @override
  String get description => 'Echoes the provided message';

  @override
  List<LLMToolParam> get parameters => const [];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      jsonEncode(args);
}

/// A progress chunk as every streaming backend now emits one.
LLMChunk _deltaChunk({String? name, String? argumentsDelta}) => LLMChunk(
  model: 'test-model',
  createdAt: DateTime(2026),
  done: false,
  message: LLMChunkMessage(
    content: null,
    role: LLMRole.assistant,
    toolCallDeltas: [
      LLMToolCallDelta(index: 0, name: name, argumentsDelta: argumentsDelta),
    ],
  ),
);

void main() {
  group('LLMToolCallDelta', () {
    test('is a value type', () {
      const a = LLMToolCallDelta(index: 0, id: 'x', name: 'f');
      const b = LLMToolCallDelta(index: 0, id: 'x', name: 'f');
      const c = LLMToolCallDelta(index: 1, id: 'x', name: 'f');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('defaults every optional part to null', () {
      const delta = LLMToolCallDelta(index: 2);

      expect(delta.index, 2);
      expect(delta.id, isNull);
      expect(delta.name, isNull);
      expect(delta.argumentsDelta, isNull);
    });
  });

  group('zero-parameter tool calls', () {
    test('a call with empty arguments executes instead of failing', () async {
      final tool = _EchoTool();
      final executor = StreamToolExecutor(
        tools: [tool],
        maxToolAttempts: 5,
        extra: null,
        streamChatCallback: (model, messages, tools, extra, attempts) =>
            Stream.value(
              LLMChunk(
                model: 'test-model',
                createdAt: DateTime(2026),
                done: true,
                message: LLMChunkMessage(
                  content: 'done',
                  role: LLMRole.assistant,
                ),
              ),
            ),
      );

      final chunks = await executor
          .executeTools(
            chunkStream: Stream.value(
              LLMChunk(
                model: 'test-model',
                createdAt: DateTime(2026),
                done: true,
                message: LLMChunkMessage(
                  content: null,
                  role: LLMRole.assistant,
                  toolCalls: [
                    // No arguments at all, as a no-parameter tool is called.
                    LLMToolCall(name: 'echo_tool', arguments: '', id: 'call_1'),
                  ],
                ),
              ),
            ),
            model: 'test-model',
            initialMessages: [LLMMessage(role: LLMRole.user, content: 'go')],
            toolAttempts: 5,
          )
          .toList();

      final toolResult = chunks.firstWhere(
        (c) => c.message?.role == LLMRole.tool,
      );
      expect(toolResult.message?.content, '{}');
      expect(toolResult.message?.content, isNot(contains('failed')));
    });
  });

  group('progress chunks are inert in llm_core', () {
    // Deltas are additive: they must not disturb the two places in llm_core
    // that fold a stream. If either of these regresses, every backend's
    // streaming tool calls silently corrupt a conversation.
    test('chatResponse folds a stream identically with and without deltas', () {
      final repo = MockLLMChatRepository();

      Future<LLMResponse> run(List<LLMChunk> chunks) async {
        repo.setStreamChunks(chunks);
        return repo.chatResponse(
          'test-model',
          messages: [LLMMessage(role: LLMRole.user, content: 'hi')],
        );
      }

      final content = LLMChunk(
        model: 'test-model',
        createdAt: DateTime(2026),
        done: false,
        message: LLMChunkMessage(content: 'Hello', role: LLMRole.assistant),
      );
      final terminal = LLMChunk(
        model: 'test-model',
        createdAt: DateTime(2026),
        done: true,
        finishReason: LLMFinishReason.stop,
        message: LLMChunkMessage(content: null, role: LLMRole.assistant),
      );

      expectLater(
        run([content, terminal]).then((r) => r.content),
        completion('Hello'),
      );
      expectLater(
        run([
          _deltaChunk(name: 'echo_tool'),
          _deltaChunk(argumentsDelta: '{"message":'),
          content,
          _deltaChunk(argumentsDelta: '"hi"}'),
          terminal,
        ]).then((r) => r.content),
        completion('Hello'),
      );
    });

    test('StreamToolExecutor collects no call from deltas alone', () async {
      final tool = _EchoTool();
      final executor = StreamToolExecutor(
        tools: [tool],
        maxToolAttempts: 5,
        extra: null,
        streamChatCallback: (model, messages, tools, extra, attempts) async* {
          fail('deltas must not trigger a tool round');
        },
      );

      final chunks = await executor
          .executeTools(
            chunkStream: Stream.fromIterable([
              _deltaChunk(name: 'echo_tool'),
              _deltaChunk(argumentsDelta: '{"message":"hi"}'),
              LLMChunk(
                model: 'test-model',
                createdAt: DateTime(2026),
                done: true,
                message: LLMChunkMessage(
                  content: 'done',
                  role: LLMRole.assistant,
                ),
              ),
            ]),
            model: 'test-model',
            initialMessages: [LLMMessage(role: LLMRole.user, content: 'hi')],
            toolAttempts: 5,
          )
          .toList();

      // Every chunk passes through untouched, and no tool ran: a fragment is
      // not an executable call.
      expect(chunks, hasLength(3));
      expect(chunks.every((c) => c.message?.role != LLMRole.tool), isTrue);
      expect(chunks.first.message?.toolCallDeltas?.single.name, 'echo_tool');
      expect(chunks.first.message?.toolCalls, isNull);
    });
  });
}
