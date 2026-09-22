import 'package:llm_core/llm_core.dart';
import 'package:llm_llamacpp/src/tool_executor.dart';
import 'package:test/test.dart';

class _EchoTool extends LLMTool {
  @override
  String get name => 'echo_tool';

  @override
  String get description => 'Echoes';

  @override
  List<LLMToolParam> get parameters => const [];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      'echoed';
}

class _NullTool extends LLMTool {
  @override
  String get name => 'null_tool';

  @override
  String get description => 'Returns null';

  @override
  List<LLMToolParam> get parameters => const [];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      null;
}

class _ThrowingTool extends LLMTool {
  @override
  String get name => 'throwing_tool';

  @override
  String get description => 'Throws';

  @override
  List<LLMToolParam> get parameters => const [];

  @override
  Future<dynamic> execute(Map<String, dynamic> args, {dynamic extra}) async =>
      throw Exception('boom');
}

Future<LLMMessage> runOne(LLMTool tool) async {
  final messages = await ToolExecutor.executeTools(
    [LLMToolCall(name: tool.name, arguments: '{}', id: 'call_1')],
    [tool],
    null,
    DefaultLLMLogger('test'),
  );
  return messages.single;
}

void main() {
  group('llama.cpp ToolExecutor', () {
    test('a successful run names its tool and is not an error', () async {
      final message = await runOne(_EchoTool());

      expect(message.role, LLMRole.tool);
      expect(message.content, 'echoed');
      expect(message.toolCallId, 'call_1');
      // This path set no tool name at all, so a history it produced left
      // Gemini's `function_result.name` empty and Claude unable to match.
      expect(message.toolName, 'echo_tool');
      expect(message.status, 'echo_tool');
      expect(message.toolResult?.isError, isFalse);
    });

    test('a null return keeps the shared wording', () async {
      final message = await runOne(_NullTool());

      expect(message.content, 'Tool null_tool returned null');
      expect(message.toolResult?.isError, isFalse);
    });

    test('a throwing tool uses the canonical failure text', () async {
      final message = await runOne(_ThrowingTool());

      // Was 'Error executing tool: $e', which no other backend produced and
      // which ClaudeMessageConverter's failure detection could never match.
      expect(
        message.content,
        startsWith('Tool throwing_tool failed: Exception: boom'),
      );
      expect(message.toolResult?.isError, isTrue);
      expect(message.toolName, 'throwing_tool');
    });
  });
}
