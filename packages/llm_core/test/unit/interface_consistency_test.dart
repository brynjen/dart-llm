/// Unit tests that verify interface consistency across backends.
///
/// These tests ensure that the core interface works consistently
/// across different backend implementations. This uses a mock repository
/// to test interface contracts without requiring actual backend connections.
///
/// **Note**: This is NOT a true integration test - it uses mocks. For actual
/// integration tests with real backends, see:
/// - packages/llm_ollama/test/integration/
/// - packages/llm_llamacpp/test/integration/
/// - test/CROSS_BACKEND_INTEGRATION.md for guidance on creating real integration tests
library;

import 'dart:convert';

import 'package:llm_core/llm_core.dart';
import 'package:test/test.dart';

import 'mock_llm_chat_repository.dart';

void main() {
  group('Interface Consistency Tests', () {
    test('streamChat interface consistency', () async {
      final repo = MockLLMChatRepository();
      repo.setResponse('Hello, world!');
      final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

      final stream = repo.streamChat('test-model', messages: messages);

      int chunkCount = 0;
      await for (final chunk in stream) {
        expect(chunk, isNotNull);
        expect(chunk.model, equals('test-model'));
        chunkCount++;
        if (chunk.done ?? false) break;
      }

      expect(chunkCount, greaterThan(0));
    });

    test('chatResponse interface consistency', () async {
      final repo = MockLLMChatRepository();
      repo.setResponse('Hello, world!');
      final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

      final response = await repo.chatResponse(
        'test-model',
        messages: messages,
      );

      expect(response, isNotNull);
      expect(response.model, equals('test-model'));
      expect(response.content, isNotNull);
      expect(response.done, isTrue);
    });

    test('StreamChatOptions works across backends', () async {
      final repo = MockLLMChatRepository();
      repo.setResponse('Response with options');
      final messages = [LLMMessage(role: LLMRole.user, content: 'Hello')];

      const options = StreamChatOptions(
        think: true,
        toolAttempts: 5,
        timeout: Duration(seconds: 30),
      );

      final stream = repo.streamChat(
        'test-model',
        messages: messages,
        options: options,
      );

      await for (final chunk in stream) {
        expect(chunk, isNotNull);
        if (chunk.done ?? false) break;
      }
    });

    test('Tool execution interface works consistently', () async {
      final repo = MockLLMChatRepository();
      final messages = [
        LLMMessage(role: LLMRole.user, content: 'Calculate 2+2'),
      ];

      final tool = _TestTool();

      // Configure mock to return tool calls
      final toolCall = LLMToolCall(
        id: 'call_123',
        name: 'test_calculator',
        arguments: jsonEncode({'expression': '2+2'}),
      );
      repo.setToolCalls([toolCall]);
      repo.setResponse('The result is 4');

      final stream = repo.streamChat(
        'test-model',
        messages: messages,
        tools: [tool],
      );

      bool toolCallReceived = false;
      String? finalContent;
      await for (final chunk in stream) {
        if (chunk.message?.toolCalls != null &&
            chunk.message!.toolCalls!.isNotEmpty) {
          toolCallReceived = true;
          expect(chunk.message!.toolCalls!.length, equals(1));
          expect(
            chunk.message!.toolCalls!.first.name,
            equals('test_calculator'),
          );
        }
        if (chunk.message?.content != null) {
          finalContent = (finalContent ?? '') + (chunk.message!.content ?? '');
        }
        if (chunk.done ?? false) break;
      }

      // Verify tool call was received in the stream
      expect(
        toolCallReceived,
        isTrue,
        reason: 'Tool call should be present in stream when tools are provided',
      );
      expect(
        finalContent,
        isNotNull,
        reason: 'Response content should be present',
      );
    });
  });
}

class _TestTool extends LLMTool {
  @override
  String get name => 'test_calculator';

  @override
  String get description => 'A test calculator tool';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'expression',
      type: 'string',
      description: 'Math expression',
      isRequired: true,
    ),
  ];

  @override
  Future<String> execute(Map<String, dynamic> args, {dynamic extra}) async {
    return '4';
  }
}
