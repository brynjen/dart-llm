import 'dart:convert';

import 'package:llm_core/llm_core.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';

/// Injects a structured-output instruction into a list of [IsolateMessage]s.
///
/// When [format] is null the original list is returned unchanged.
/// When [format] is non-null a schema instruction is either:
/// - appended to the existing `system` message (if one is present), or
/// - prepended as a new `system` message (if none exists).
///
/// This function is package-private (no leading `_`) so it can be
/// imported and unit-tested directly.
List<IsolateMessage> injectResponseFormat(
  List<IsolateMessage> messages,
  LLMResponseFormat? format,
) {
  if (format == null) return messages;

  final instruction = switch (format) {
    JsonFormat() =>
      'Respond with valid JSON only. '
      'Do not include any explanation or text outside the JSON.',
    JsonSchemaFormat() =>
      'Respond with valid JSON only, conforming exactly to the following '
      'JSON Schema. Do not include any explanation or text outside the '
      'JSON.\n\nSchema:\n${json.encode(format.schema)}',
  };

  final systemIndex = messages.indexWhere((m) => m.role == 'system');
  if (systemIndex >= 0) {
    final updated = List<IsolateMessage>.from(messages);
    updated[systemIndex] = IsolateMessage(
      role: 'system',
      content: '${messages[systemIndex].content}\n\n$instruction',
    );
    return updated;
  }

  return [IsolateMessage(role: 'system', content: instruction), ...messages];
}
