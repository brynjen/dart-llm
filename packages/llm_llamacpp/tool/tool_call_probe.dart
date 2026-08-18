// Copyright 2024 The dart-llm Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Exercises multi-turn tool calling against a real GGUF on the host.
///
/// Tool-calling bugs in a local backend are behavioural: they only show up once a
/// real model reads a real prompt. Driving that through the Flutter example app
/// is slow and flaky, so this script runs the same code path headless and prints
/// what actually happened on each turn.
///
/// It exists specifically to catch the failure where a model calls a tool on the
/// first turn and then stops on every turn after, because the replayed history
/// showed it announcing a tool and answering without calling one.
///
/// Usage:
/// ```
/// LLM_LLAMACPP_LIB_DIR=<dir containing libllama.dylib> \
///   dart run tool/tool_call_probe.dart <model.gguf> [--no-history-fix]
/// ```
///
/// `--no-history-fix` replays only the visible assistant text, reproducing the
/// old behaviour so the two can be compared side by side.
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';

/// A calculator whose invocations are recorded, so the script can report whether
/// the tool actually ran rather than trusting the model's prose.
class ProbeCalculator extends LLMTool {
  /// Every (arguments, result) pair this tool was called with.
  final List<(Map<String, dynamic>, String)> invocations = [];

  @override
  String get name => 'calculator';

  @override
  String get description =>
      'Performs basic mathematical operations: addition, subtraction, '
      'multiplication, and division';

  @override
  List<LLMToolParam> get parameters => [
    LLMToolParam(
      name: 'operation',
      type: 'string',
      description: 'The mathematical operation to perform',
      enums: ['add', 'subtract', 'multiply', 'divide'],
      isRequired: true,
    ),
    LLMToolParam(
      name: 'a',
      type: 'number',
      description: 'The first number',
      isRequired: true,
    ),
    LLMToolParam(
      name: 'b',
      type: 'number',
      description: 'The second number',
      isRequired: true,
    ),
  ];

  @override
  Future<String> execute(Map<String, dynamic> args, {dynamic extra}) async {
    final a = (args['a'] as num?)?.toDouble();
    final b = (args['b'] as num?)?.toDouble();
    final op = args['operation'];
    if (a == null || b == null || op is! String) {
      const err = 'Error: expected operation, a and b';
      invocations.add((args, err));
      return err;
    }
    final (value, symbol) = switch (op) {
      'add' => (a + b, '+'),
      'subtract' => (a - b, '-'),
      'multiply' => (a * b, '×'),
      'divide' => b == 0 ? (double.nan, '÷') : (a / b, '÷'),
      _ => (double.nan, '?'),
    };
    final result = '${_fmt(a)} $symbol ${_fmt(b)} = ${_fmt(value)}';
    invocations.add((args, result));
    return result;
  }

  static String _fmt(double v) {
    if (v.isNaN) return 'NaN';
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsFixed(4);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }
}

/// One completed turn.
class TurnOutcome {
  TurnOutcome({
    required this.prompt,
    required this.visibleText,
    required this.toolCalls,
    required this.rawContent,
  });

  final String prompt;
  final String visibleText;
  final List<LLMToolCall> toolCalls;
  final String? rawContent;

  bool get calledTool => toolCalls.isNotEmpty;
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/tool_call_probe.dart <model.gguf> '
      '[--no-history-fix]',
    );
    exitCode = 64;
    return;
  }
  final modelPath = positional.first;
  if (!File(modelPath).existsSync()) {
    stderr.writeln('model not found: $modelPath');
    exitCode = 66;
    return;
  }
  final historyFix = !args.contains('--no-history-fix');

  print('model:       $modelPath');
  print(
    'lib dir:     ${Platform.environment['LLM_LLAMACPP_LIB_DIR'] ?? '(unset)'}',
  );
  print(
    'history fix: ${historyFix ? 'ON (replay tool call + result)' : 'OFF (visible text only)'}',
  );
  print('');

  final calculator = ProbeCalculator();

  // Deliberately typed as the interface. The point of this probe is the public
  // contract a consumer codes against, so nothing below may reach for a
  // llamacpp-specific member.
  final LLMChatRepository repo = LlamaCppChatRepository.withModelPath(
    modelPath,
    nGpuLayers: 0,
  );

  // Rebuilt fresh for each request, exactly as an app would.
  final history = <LLMMessage>[];
  const systemPrompt =
      'You are a helpful assistant. Answer questions concisely and accurately.';

  final questions = [
    'What is 347 multiplied by 89?',
    'What is 1234 times 5678?',
    'And what is 55 plus 45?',
  ];

  final outcomes = <TurnOutcome>[];

  for (var turn = 0; turn < questions.length; turn++) {
    final question = questions[turn];
    history.add(LLMMessage(role: LLMRole.user, content: question));

    final messages = [
      LLMMessage(role: LLMRole.system, content: systemPrompt),
      ...history,
    ];

    final callsBefore = calculator.invocations.length;
    final visible = StringBuffer();
    final calls = <LLMToolCall>[];
    String? raw;

    await for (final chunk in repo.streamChat(
      'lfm2.5',
      messages: messages,
      tools: [calculator],
    )) {
      final content = chunk.message?.content;
      if (content != null) visible.write(content);
      final chunkCalls = chunk.message?.toolCalls;
      if (chunkCalls != null && chunkCalls.isNotEmpty) {
        calls.addAll(chunkCalls);
        raw ??= chunk.message?.rawContent;
      }
    }

    final newInvocations = calculator.invocations.sublist(callsBefore);

    print('─' * 76);
    print('TURN ${turn + 1}: $question');
    print('─' * 76);
    print('  tool calls parsed : ${calls.length}');
    for (final c in calls) {
      print('    ${c.name}(${c.arguments})');
    }
    print('  tool executed     : ${newInvocations.length}');
    for (final (a, r) in newInvocations) {
      print('    ${json.encode(a)} -> $r');
    }
    print('  raw turn          : ${raw == null ? '(none)' : _oneLine(raw)}');
    print('  visible answer    : ${_oneLine(visible.toString())}');
    print('');

    outcomes.add(
      TurnOutcome(
        prompt: question,
        visibleText: visible.toString().trim(),
        toolCalls: calls,
        rawContent: raw,
      ),
    );

    // Append this turn to history, the way a UI keeping its own transcript must.
    if (calls.isNotEmpty && historyFix) {
      // The documented LFM2 shape: the assistant turn that issued the call
      // (markup intact), then the tool result, then the assistant's answer.
      history.add(
        LLMMessage(
          role: LLMRole.assistant,
          content: raw ?? visible.toString().trim(),
        ),
      );
      // `Validation.validateMessages` requires a tool message to name the call
      // it answers, so pair results with calls by position — ToolExecutor runs
      // them in order.
      for (var i = 0; i < newInvocations.length; i++) {
        history.add(
          LLMMessage(
            role: LLMRole.tool,
            content: newInvocations[i].$2,
            toolCallId: i < calls.length ? calls[i].id : null,
          ),
        );
      }
      if (visible.toString().trim().isNotEmpty) {
        history.add(
          LLMMessage(
            role: LLMRole.assistant,
            content: visible.toString().trim(),
          ),
        );
      }
    } else {
      history.add(
        LLMMessage(
          role: LLMRole.assistant,
          content: visible.toString().trim().isEmpty
              ? '(no answer)'
              : visible.toString().trim(),
        ),
      );
    }
  }

  if (repo is LlamaCppChatRepository) repo.dispose();
  // The inference isolate is a long-lived singleton, so the VM will not exit
  // while it is alive. Kill it so this script can be used as a CI gate.
  PersistentInferenceIsolate.instance.dispose();

  print('=' * 76);
  print('SUMMARY  (history fix ${historyFix ? 'ON' : 'OFF'})');
  print('=' * 76);
  for (var i = 0; i < outcomes.length; i++) {
    final o = outcomes[i];
    print(
      '  turn ${i + 1}: '
      '${o.calledTool ? 'CALLED TOOL' : 'no tool call'}  |  ${o.prompt}',
    );
  }
  final called = outcomes.where((o) => o.calledTool).length;
  print('');
  print('  $called/${outcomes.length} turns used the tool');
  // Non-zero exit when a later turn stopped calling the tool, so this can gate.
  if (called != outcomes.length) exitCode = 1;
}

String _oneLine(String s) {
  final flat = s.replaceAll('\n', '\\n').trim();
  return flat.length > 160 ? '${flat.substring(0, 160)}…' : flat;
}
