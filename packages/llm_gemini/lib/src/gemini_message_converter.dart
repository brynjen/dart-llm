import 'package:llm_core/llm_core.dart';

/// Converts [LLMMessage] lists and [LLMTool] declarations to the Gemini
/// Interactions API request format.
///
/// Key differences from the legacy `generateContent` format:
/// - Turns live in a top-level `input` array instead of `contents`.
/// - A turn's payload is a list of typed content *blocks*
///   (`{"type": "text", …}`) instead of untyped `parts`.
/// - Tool results are `function_result` blocks instead of `functionResponse`
///   parts.
/// - Tool declarations are flat `{"type": "function", "name": …}` objects
///   instead of being nested under `tools[].functionDeclarations`.
class GeminiMessageConverter {
  /// Serializes a full conversation into the Interactions API `input` array.
  ///
  /// ## ⚠️ UNVERIFIED WIRE SHAPE — CHECK HERE FIRST ON HTTP 400
  ///
  /// [LLMChatRepository.streamChat] is stateless: it receives the entire
  /// conversation on every call, so requests are sent with `store: false` and
  /// the whole history serialized here rather than relying on
  /// `previous_interaction_id`.
  ///
  /// Google's documentation states that `input` accepts "a plain string, a list
  /// of typed content objects, or a list of role-tagged turns (for stateless
  /// history)", but the exact JSON of a role-tagged turn is **not documented in
  /// any source available when this was written**. The shape produced here is
  /// an informed assumption:
  ///
  /// ```json
  /// [
  ///   {"role": "user",  "content": [{"type": "text", "text": "…"}]},
  ///   {"role": "model", "content": [{"type": "text", "text": "…"}]}
  /// ]
  /// ```
  ///
  /// Every assumption about that envelope is confined to this one function so
  /// there is a single place to fix. Specifically, the following are inferred
  /// rather than read from documentation:
  /// - the `{"role": …, "content": [...]}` turn envelope itself;
  /// - `"model"` as the assistant role name (carried over from
  ///   `generateContent`, where Gemini uses `model` rather than `assistant`);
  /// - system messages being emitted as leading `user` turns, because the
  ///   Interactions request body has no documented system-instruction field;
  /// - the `{"type": "function_call", "id", "name", "arguments"}` block used to
  ///   echo a previous assistant tool call back (modeled on the `step.start`
  ///   event payload for a `function_call` step);
  /// - the `{"type": "image", "mime_type", "data"}` block (modeled on the
  ///   `step.delta` image delta);
  /// - `function_result` blocks being carried on a `user` turn.
  ///
  /// The `function_result` block *content* is documented:
  /// `{"type": "function_result", "call_id": …, "name": …, "result": [{"type":
  /// "text", "text": …}]}`.
  ///
  /// Known limitation: `thought_signature` values observed on the response
  /// stream are surfaced through `LLMChunk.providerMetadata`, but there is no
  /// documented input block for echoing them back, so multi-turn function
  /// calling may still hit "Function call is missing a thought_signature".
  static List<Map<String, dynamic>> buildStatelessInput(
    List<LLMMessage> messages,
  ) {
    final turns = <Map<String, dynamic>>[];

    void addTurn(String role, List<Map<String, dynamic>> content) {
      turns.add(<String, dynamic>{'role': role, 'content': content});
    }

    for (final msg in messages) {
      switch (msg.role) {
        case LLMRole.system:
          if (msg.content != null && msg.content!.isNotEmpty) {
            addTurn('user', [_textBlock(msg.content!)]);
          }

        case LLMRole.user:
          final content = <Map<String, dynamic>>[];
          for (final image in msg.images ?? const <String>[]) {
            content.add(_imageBlock(image));
          }
          if (msg.content != null && msg.content!.isNotEmpty) {
            content.add(_textBlock(msg.content!));
          }
          addTurn('user', content.isEmpty ? [_textBlock('')] : content);

        case LLMRole.assistant:
          final content = <Map<String, dynamic>>[];
          if (msg.content != null && msg.content!.isNotEmpty) {
            content.add(_textBlock(msg.content!));
          }
          for (final toolCall in msg.toolCalls ?? const <LLMToolCall>[]) {
            Map<String, dynamic> arguments;
            try {
              arguments = toolCall.argumentsJson;
            } catch (_) {
              arguments = <String, dynamic>{};
            }
            content.add(<String, dynamic>{
              'type': 'function_call',
              if (toolCall.id != null && toolCall.id!.isNotEmpty)
                'id': toolCall.id,
              'name': toolCall.name,
              'arguments': arguments,
            });
          }
          addTurn('model', content.isEmpty ? [_textBlock('')] : content);

        case LLMRole.tool:
          final block = _functionResultBlock(msg);
          // Consecutive tool results belong to the same turn: one assistant
          // turn may request several calls in parallel.
          if (turns.isNotEmpty &&
              turns.last['role'] == 'user' &&
              _isFunctionResultTurn(turns.last)) {
            (turns.last['content'] as List<Map<String, dynamic>>).add(block);
          } else {
            addTurn('user', [block]);
          }
      }
    }

    return turns;
  }

  /// Converts an [LLMTool] to an Interactions API tool entry.
  ///
  /// The Interactions API takes a flat array of tool objects — unlike
  /// `generateContent`, which wraps declarations in
  /// `tools[0].functionDeclarations`:
  /// ```json
  /// {"type": "function", "name": "…", "description": "…", "parameters": {…}}
  /// ```
  static Map<String, dynamic> toolToFunctionSpec(LLMTool tool) {
    final openAiFormat = tool.toJson;
    final function = openAiFormat['function'] as Map<String, dynamic>? ?? {};
    final parameters = function['parameters'] as Map<String, dynamic>? ?? {};
    return <String, dynamic>{
      'type': 'function',
      'name': function['name'] ?? tool.name,
      'description': function['description'] ?? tool.description,
      'parameters': parameters,
    };
  }

  static Map<String, dynamic> _textBlock(String text) => <String, dynamic>{
    'type': 'text',
    'text': text,
  };

  /// Builds a documented `function_result` block from a tool-result message.
  ///
  /// [LLMMessage.toolCallId] carries the id of the call being answered and
  /// [LLMMessage.status] carries the tool name, matching how
  /// [StreamToolExecutor] populates tool messages.
  static Map<String, dynamic> _functionResultBlock(LLMMessage msg) {
    return <String, dynamic>{
      'type': 'function_result',
      'call_id': msg.toolCallId ?? '',
      'name': msg.status ?? '',
      'result': [_textBlock(msg.content ?? '')],
    };
  }

  static bool _isFunctionResultTurn(Map<String, dynamic> turn) {
    final content = turn['content'];
    if (content is! List || content.isEmpty) return false;
    return (content.first as Map<String, dynamic>)['type'] == 'function_result';
  }

  /// Builds an image block, sniffing the MIME type from a data URI or from the
  /// leading bytes of a bare base64 payload.
  static Map<String, dynamic> _imageBlock(String imageData) {
    String mimeType = 'image/jpeg';
    String data = imageData;

    if (imageData.startsWith('data:')) {
      final commaIdx = imageData.indexOf(',');
      if (commaIdx != -1) {
        final header = imageData.substring(5, commaIdx);
        final semicolonIdx = header.indexOf(';');
        if (semicolonIdx != -1) {
          mimeType = header.substring(0, semicolonIdx);
        }
        data = imageData.substring(commaIdx + 1);
      }
    } else if (imageData.startsWith('/9j/')) {
      mimeType = 'image/jpeg';
    } else if (imageData.startsWith('iVBORw0KGgo')) {
      mimeType = 'image/png';
    } else if (imageData.startsWith('R0lGOD')) {
      mimeType = 'image/gif';
    } else if (imageData.startsWith('UklGR')) {
      mimeType = 'image/webp';
    }

    return <String, dynamic>{
      'type': 'image',
      'mime_type': mimeType,
      'data': data,
    };
  }
}
