/// Long-context probe: buries a fact near the start of a ~150k-token prompt
/// and asks the model to retrieve it. Exercises prefill at scale and
/// verifies the served 204800-token window is actually usable end-to-end
/// through VLLMChatRepository (timeouts, streaming, usage reporting).
library;

import 'dart:io';

import 'package:llm_vllm/llm_vllm.dart';

Future<void> main(List<String> args) async {
  final baseUrl =
      Platform.environment['VLLM_BASE_URL'] ?? 'http://localhost:8000';
  final model = Platform.environment['VLLM_CHAT_MODEL'] ?? 'Qwen/Qwen3-0.6B';
  final targetTokens = args.isNotEmpty ? int.parse(args[0]) : 150000;

  // ~2.9 chars/token, measured against Qwen's tokenizer for exactly this
  // filler: digits fragment into near-one-token-per-character, so the usual
  // ~4 chars/token English estimate overshoots the context window by ~35%.
  // Sentences vary to defeat prefix caching and keep attention honest.
  const charsPerToken = 2.9;
  final filler = StringBuffer();
  var sentence = 0;
  while (filler.length < targetTokens * charsPerToken) {
    filler.write(
      'Log entry ${sentence++}: sensor ${sentence % 97} reported '
      '${(sentence * 37) % 1000} units at offset ${(sentence * 13) % 86400}. ',
    );
  }

  const needle = 'The maintenance password is "glacier-accordion-42".';
  final prompt =
      '$needle\n\n$filler\n\n'
      'What is the maintenance password stated at the very beginning of '
      'this document? Reply with only the password.';

  stdout.writeln(
    'prompt size: ~${prompt.length} chars '
    '(~${prompt.length ~/ charsPerToken} tokens, target $targetTokens)',
  );

  final repo = VLLMChatRepository(
    baseUrl: baseUrl,
    timeoutConfig: const TimeoutConfig(
      readTimeout: Duration(minutes: 5),
      totalTimeout: Duration(minutes: 10),
    ),
  );
  final started = Stopwatch()..start();
  try {
    final response = await repo.chatResponse(
      model,
      messages: [LLMMessage(role: LLMRole.user, content: prompt)],
      options: const LLMChatOptions(think: false, maxOutputTokens: 64),
    );
    started.stop();
    stdout.writeln(
      'prompt tokens (server-counted): ${response.promptEvalCount}',
    );
    stdout.writeln('completion tokens: ${response.evalCount}');
    stdout.writeln(
      'wall time: ${(started.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
    );
    stdout.writeln('answer: ${response.content?.trim()}');
    final found = response.content?.contains('glacier-accordion-42') ?? false;
    stdout.writeln(
      found
          ? 'PASS: needle retrieved across the full context'
          : 'FAIL: needle not retrieved',
    );
    exitCode = found ? 0 : 1;
  } finally {
    repo.close();
  }
}
