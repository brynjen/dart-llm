import 'dart:convert';

import 'package:llm_llamacpp/src/tool_calls/tool_call_syntax.dart';

/// Renders tool definitions the way a model family expects to receive them.
///
/// `llama_chat_apply_template` takes only role/content pairs — the C API has no
/// `tools` parameter, so the `{%- if tools -%}` branch in a GGUF chat template is
/// unreachable from here. The tool list therefore has to be written into the
/// system message by hand, in exactly the shape the template would have produced,
/// so the model sees what it was fine-tuned on.
///
/// [schemas] are OpenAI-style function schemas, i.e. the `function` object of
/// `LLMTool.toJson`: `{"name", "description", "parameters"}`.
String? formatToolDefinitions(
  List<Map<String, dynamic>> schemas,
  ToolCallFormat format,
) {
  if (schemas.isEmpty) return null;

  return switch (format) {
    // LFM2/LFM2.5's template appends exactly this to the system prompt, then
    // expects Pythonic calls back. Verified against LiquidAI's published
    // chat_template.jinja for LFM2.5-1.2B-Instruct.
    ToolCallFormat.lfm2 =>
      'List of tools: [${schemas.map(json.encode).join(', ')}]',

    // Hermes/Qwen templates emit a <tools> block plus an instruction to reply
    // inside <tool_call> tags.
    ToolCallFormat.hermes =>
      '# Tools\n\nYou may call one or more functions to assist with the user '
          'query.\n\nYou are provided with function signatures within '
          '<tools></tools> XML tags:\n<tools>\n'
          '${schemas.map(json.encode).join('\n')}\n'
          '</tools>\n\nFor each function call, return a json object with the '
          'function name and arguments within <tool_call></tool_call> XML '
          'tags:\n<tool_call>\n{"name": <function-name>, "arguments": '
          '<args-json-object>}\n</tool_call>',

    ToolCallFormat.mistral =>
      '[AVAILABLE_TOOLS][${schemas.map(json.encode).join(', ')}][/AVAILABLE_TOOLS]',

    // Llama 3.x pythonic: the model is told to answer with a bracketed call list.
    ToolCallFormat.llama3Pythonic || ToolCallFormat.pythonic =>
      'You have access to the following functions:\n\n'
          '${schemas.map(json.encode).join('\n')}\n\n'
          'If you choose to call a function, reply with a bracketed list of '
          'calls and nothing else, for example: '
          '[func_name(param1="value", param2=3)]',

    // Anything else: ask for JSON, which is what the previous behaviour
    // effectively required callers to prompt for themselves.
    ToolCallFormat.json =>
      'You have access to the following tools:\n\n'
          '${schemas.map(json.encode).join('\n')}\n\n'
          'To call a tool, reply with JSON only, in the form '
          '{"name": "tool_name", "arguments": {...}}. Do not include any text '
          'outside the JSON.',
  };
}
